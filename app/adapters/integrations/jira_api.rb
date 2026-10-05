module Integrations
  # Calls to Jira Cloud's REST API through Atlassian's gateway with the token of Firefight's own OAuth 2.0 (3LO) app,
  # for keeping incident items in step with issues. A site's requests go to https://api.atlassian.com/ex/jira/<cloud id>,
  # its cloud id read from the token's accessible resources (developer.atlassian.com/cloud/jira/platform/oauth-2-3lo-apps).
  # Issues, transitions and user search are the REST API v3's (developer.atlassian.com/cloud/jira/platform/rest/v3), and
  # webhooks are the dynamic ones an OAuth 2.0 app registers, which lapse after 30 days unless refreshed
  # (developer.atlassian.com/cloud/jira/platform/webhooks).
  class JiraApi
    class Error < Integrations::Error; end

    GATEWAY = "https://api.atlassian.com".freeze
    PROVIDER = "Jira".freeze
    # Jira words a refusal in errorMessages, or per field in errors.
    REASON = lambda do |body|
      next unless body.is_a?(Hash)

      Array(body["errorMessages"]).first.presence || body["errors"].to_h.values.first.presence || body["message"].presence
    end

    def initialize(headers)
      @headers = headers
    end

    # The sites the token reaches, each with its cloud id and address.
    def resources = Array(request(:get, "#{GATEWAY}/oauth/token/accessible-resources"))

    # The cloud id of the site at host, such as acme.atlassian.net.
    def cloud_id(host)
      found = resources.find { |resource| URI.parse(resource["url"].to_s).host.to_s.casecmp?(host.to_s) }
      found&.dig("id") || raise(Error, "Firefight's Jira app does not reach #{host}. Connect it to that site.")
    end

    def issue(cloud, key, fields) = request(:get, site(cloud, "issue/#{Http.segment(key)}?fields=#{fields.join(',')}"))

    def create_issue(cloud, fields) = request(:post, site(cloud, "issue"), { "fields" => fields })

    def edit_issue(cloud, key, fields) = request(:put, site(cloud, "issue/#{Http.segment(key)}"), { "fields" => fields })

    def transitions(cloud, key) = request(:get, site(cloud, "issue/#{Http.segment(key)}/transitions"))

    def transition(cloud, key, id) = request(:post, site(cloud, "issue/#{Http.segment(key)}/transitions"), { "transition" => { "id" => id } })

    def users(cloud, query) = Array(request(:get, site(cloud, "user/search?query=#{CGI.escape(query)}")))

    # Registers one webhook for jira:issue_updated and jira:issue_deleted on the issues the JQL matches. Answers its id.
    def register_webhook(cloud, url, jql)
      body = request(:post, site(cloud, "webhook"), { "url" => url, "webhooks" => [ { "events" => %w[jira:issue_updated jira:issue_deleted], "jqlFilter" => jql } ] })
      result = Array(body["webhookRegistrationResult"]).first.to_h
      result["createdWebhookId"] || raise(Error, Array(result["errors"]).first || "Jira did not register the webhook.")
    end

    def delete_webhook(cloud, id) = request(:delete, site(cloud, "webhook"), { "webhookIds" => [ id.to_i ] })

    # Answers when the webhook now lapses.
    def refresh_webhook(cloud, id) = request(:put, site(cloud, "webhook/refresh"), { "webhookIds" => [ id.to_i ] })["expirationDate"]

    private

    def site(cloud, path) = "#{GATEWAY}/ex/jira/#{Http.segment(cloud)}/rest/api/3/#{path}"

    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.freeze

    def request(verb, url, payload = nil)
      uri = URI.parse(url)
      request = VERBS.fetch(verb).new(uri)
      @headers.each { |name, value| request[name] = value }
      request["Accept"] = "application/json"
      if payload
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
      end
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON)
    end
  end
end
