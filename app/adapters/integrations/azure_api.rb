module Integrations
  # Calls to Azure Resource Manager and the Log Analytics query API with a workspace's own service principal, for the
  # Azure integration. The principal's client secret is traded for an access token per audience (the client credentials
  # grant of the Microsoft identity platform), cached on the environment row until close to expiry. Each of Azure's
  # clouds has its own hosts for all three.
  class AzureApi
    class Error < Integrations::Error; end
    class Forbidden < Error; end
    # Resource Manager answered that the resource is not there, the one answer a re-read takes as gone.
    class NotFound < Error
      include Integrations::NotFound
    end

    # Where one of Azure's clouds signs in, runs Resource Manager and answers Log Analytics queries. A token's scope is
    # its audience's host followed by /.default. The hosts are the ones Microsoft documents: sign-in on Microsoft Entra's
    # national clouds page, Resource Manager on its control plane page, and Log Analytics in the Azure Monitor Query
    # libraries' sovereign cloud examples.
    Cloud = Data.define(:login, :management, :log_analytics) do
      def host(audience) = public_send(audience)

      def scope(audience) = "#{host(audience)}/.default"
    end
    GLOBAL = Cloud.new(login: "https://login.microsoftonline.com", management: "https://management.azure.com",
                       log_analytics: "https://api.loganalytics.io")
    US_GOVERNMENT = Cloud.new(login: "https://login.microsoftonline.us", management: "https://management.usgovcloudapi.net",
                              log_analytics: "https://api.loganalytics.us")
    CHINA = Cloud.new(login: "https://login.partner.microsoftonline.cn", management: "https://management.chinacloudapi.cn",
                      log_analytics: "https://api.loganalytics.azure.cn")
    # Microsoft Entra puts its reason in error_description, with a trace on the lines after it.
    OAUTH_REASON = ->(body) { Sentence.clean(body["error_description"]) || body["error"].presence }
    MANAGEMENT = :management
    LOG_ANALYTICS = :log_analytics
    TOKEN_CACHE_KEY = "azure_tokens".freeze
    TOKEN_REFRESH_MARGIN = 5.minutes
    FORBIDDEN = 403
    NOT_FOUND = 404
    ACTIVITY_LOG_VERSION = "2015-04-01".freeze
    # The fields of an activity log event Firefight reads, the rest left out of the answer ($select).
    ACTIVITY_LOG_FIELDS = %w[eventDataId eventTimestamp operationName resourceId status].freeze
    PAGE_LIMIT = 10
    METRICS_VERSION = "2023-10-01".freeze
    # Azure names a tenant, a principal and a subscription by GUID.
    GUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

    attr_reader :subscription

    # token_cache is the ConnectionSettings the tokens are kept with, or nil to keep them for this client only.
    def initialize(tenant:, client_id:, client_secret:, subscription:, cloud: GLOBAL, token_cache: nil)
      @cloud = cloud
      @tenant = tenant
      @client_id = client_id
      @client_secret = client_secret
      @subscription = subscription
      @token_cache = token_cache
      @tokens = {}
    end

    def subscription_details = get("/subscriptions/#{segment(@subscription)}", "2022-12-01")

    # Every subscription the principal holds a role on, each with its subscriptionId, displayName and state, following
    # nextLink (Subscriptions, List, 2022-12-01, learn.microsoft.com/rest/api/resources/subscriptions/list). Reader on a
    # subscription is enough to see it. No subscription of its own is needed to ask.
    def subscriptions = list("/subscriptions", "2022-12-01")

    # A Resource Manager read, by path from the root and the api-version that resource type takes.
    def get(path, api_version, query = {}) = arm(Net::HTTP::Get, path, api_version, nil, query)

    def post(path, api_version, body = nil) = arm(Net::HTTP::Post, path, api_version, body)

    def patch(path, api_version, body) = arm(Net::HTTP::Patch, path, api_version, body)

    def put(path, api_version, body) = arm(Net::HTTP::Put, path, api_version, body)

    # Every page of a Resource Manager list, following nextLink up to PAGE_LIMIT pages, as a Pages::Read that says
    # whether it holds all of it.
    def list(path, api_version, query = {})
      Pages.read(max_pages: PAGE_LIMIT) do |link|
        page = link ? next_page(link) : get(path, api_version, query)
        [ page["value"], page["nextLink"] ]
      end
    end

    # A Kusto query over the logs of one resource, by its Resource Manager id, whatever Log Analytics workspace keeps them.
    # The id goes into the path as it is, after v1/ (Query_ExecuteWithResourceId).
    def query_resource_logs(resource_id, query, timespan) = log_query("#{@cloud.log_analytics}/v1/#{resource_id.delete_prefix('/')}/query", query, timespan)

    # A Kusto query over one Log Analytics workspace, by its customer id (Query_Execute).
    def query_workspace_logs(workspace_id, query, timespan) = log_query("#{@cloud.log_analytics}/v1/workspaces/#{segment(workspace_id)}/query", query, timespan)

    # Azure Monitor's metrics of one resource (Metrics_List), with the parameters as the API names them.
    def metrics(resource_id, query) = get("#{resource_id}/providers/Microsoft.Insights/metrics", METRICS_VERSION, query)

    # The subscription's activity log between two times, every page up to PAGE_LIMIT, as a Pages::Read (Activity Logs,
    # List, 2015-04-01, with the filter pattern for a subscription in a time range, which is the only form that reads it
    # all). Reader may read it.
    def activity_log(from, to)
      filter = "eventTimestamp ge '#{from.utc.iso8601(6)}' and eventTimestamp le '#{to.utc.iso8601(6)}'"
      list("/subscriptions/#{segment(@subscription)}/providers/Microsoft.Insights/eventtypes/management/values", ACTIVITY_LOG_VERSION,
           "$filter" => filter, "$select" => ACTIVITY_LOG_FIELDS.join(","))
    end

    def segment(value) = Http.segment(value)

    private

    def log_query(url, query, timespan)
      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { "query" => query, "timespan" => timespan }.to_json
      answer = send_request(uri, request, LOG_ANALYTICS)
      # A query that ran in part answers 200 with an error beside its tables, and what it says is part of the answer.
      raise Error, "Log Analytics answered in part: #{answer.dig('error', 'message')}" if answer["error"].present? && Array(answer["tables"]).empty?

      answer
    end

    # The token goes only to the cloud's own Resource Manager, whatever a page names as the next one.
    def next_page(link)
      uri = URI.parse(link)
      raise Error, "Azure named a next page outside Resource Manager, so the list stops here" unless uri.host == URI.parse(@cloud.management).host

      send_request(uri, Net::HTTP::Get.new(uri), MANAGEMENT)
    end

    def arm(verb, path, api_version, body, query = {})
      uri = URI.parse("#{@cloud.management}#{path}")
      uri.query = URI.encode_www_form(query.compact.merge("api-version" => api_version))
      request = verb.new(uri)
      unless body.nil?
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request, MANAGEMENT)
    end

    def send_request(uri, request, audience)
      request["Authorization"] = "Bearer #{access_token(audience)}"
      Http.json(uri, request, error_class: Error, provider_name: "Azure", refine: ->(code, _reason) { { FORBIDDEN => Forbidden, NOT_FOUND => NotFound }[code] })
    end

    def access_token(audience)
      cached = @token_cache&.credential(TOKEN_CACHE_KEY)&.dig(audience.to_s)
      if cached.present?
        expires_at = Time.zone.parse(cached["expires_at"].to_s)
        return cached["token"] if expires_at && expires_at > TOKEN_REFRESH_MARGIN.from_now
      end
      held = @tokens[audience]
      return held[:token] if held && held[:expires_at] > TOKEN_REFRESH_MARGIN.from_now

      mint_token(audience)
    end

    def mint_token(audience)
      uri = URI.parse("#{@cloud.login}/#{segment(@tenant)}/oauth2/v2.0/token")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data("grant_type" => "client_credentials", "client_id" => @client_id, "client_secret" => @client_secret,
                            "scope" => @cloud.scope(audience))
      body = Http.json(uri, request, error_class: Error, provider_name: "Microsoft", reason: OAUTH_REASON)
      raise Error, "Microsoft answered with no access token" if body["access_token"].blank?

      expires_at = body["expires_in"].to_i.seconds.from_now
      @tokens[audience] = { token: body["access_token"], expires_at: expires_at }
      if @token_cache
        tokens = @token_cache.credential(TOKEN_CACHE_KEY).to_h.merge(audience.to_s => { "token" => body["access_token"], "expires_at" => expires_at.utc.iso8601 })
        @token_cache.store_credential!(TOKEN_CACHE_KEY, tokens)
      end
      body["access_token"]
    end
  end
end
