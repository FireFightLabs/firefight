module Integrations
  # Calls to Azure DevOps Services' REST API (7.1, learn.microsoft.com/rest/api/azure/devops) for one organization, with
  # a personal access token sent as HTTP Basic with an empty user, as Microsoft documents for a PAT (Use personal access
  # tokens, Use a PAT). Every path is written after the organization, such as /web/_apis/build/builds, and the releases of
  # classic release pipelines answer on their own host, vsrm.dev.azure.com, as the Release API reference gives it.
  class AzureDevopsApi
    class Error < Integrations::Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # The token is not accepted, or may not do this.
    class Refused < Error; end

    HOST = "dev.azure.com".freeze
    RELEASE_HOST = "vsrm.dev.azure.com".freeze
    API_VERSION = "7.1".freeze
    VERSION_PARAM = "api-version".freeze
    PROVIDER_KEY = "azure_devops".freeze
    PROVIDER = "Azure DevOps".freeze
    # A list answers { count, value } and says where the next page starts in this header (Builds - List, continuationToken).
    CONTINUATION = "x-ms-continuationtoken".freeze
    CONTINUATION_PARAM = "continuationToken".freeze
    PAGE_SIZE = 100
    # The Release API's paths, which only its own host answers.
    RELEASE_PATH = %r{\A/[^/]+/_apis/release(/|\z)}i
    ORGANIZATION = /\A[A-Za-z0-9][A-Za-z0-9-]{0,49}\z/
    # Azure DevOps reads the reason a call failed from message (its error shape, typeKey and message).
    REASON = ->(body) { body["message"].presence || body["typeKey"].presence }
    REFINED = { 401 => Refused, 403 => Refused, 404 => NotFound }.freeze
    REFINE = ->(code, _reason) { REFINED[code] }
    # A token Azure DevOps does not accept can be answered with its sign in page and 203 rather than a refusal, which
    # would otherwise read as an empty answer.
    NOT_AUTHORITATIVE = 203
    # A job's log can be long, and only its end usually says why it failed.
    TEXT_LIMIT = 2_000_000

    attr_reader :organization

    def initialize(organization, token)
      @organization = organization.to_s.strip
      raise Error, "The organization is its name after dev.azure.com/, such as fabrikam." unless @organization.match?(ORGANIZATION)

      @token = token
    end

    # A project's path, its name one encoded segment, so a project called Fabrikam Fiber is still one.
    def self.project(name) = "/#{Http.segment(name)}"

    # A repository's path inside its project, by its name or id.
    def self.repository(project, repository) = "#{project(project)}/_apis/git/repositories/#{Http.segment(repository)}"

    def get(path, query = {}) = call(Net::HTTP::Get, path, query)

    # Any GET of the API, by its path after the organization, for the general read (Integrations::ApiReads), which checks
    # the path before it gets here.
    def read(path, query) = get(path, query)

    # A list's values, reading on from each page's continuation token up to pages. Returns the values and whether more
    # were left.
    def list(path, query = {}, pages: 1)
      read = Pages.read(max_pages: pages) do |token|
        answer = call(Net::HTTP::Get, path, token ? query.merge(CONTINUATION_PARAM => token) : query, with_status: true)
        [ values(answer.body), answer.header(CONTINUATION).to_s ]
      end
      [ read.items, read.incomplete? ]
    end

    # Plain text, such as a job's log, cut to TEXT_LIMIT from the end, where a job says why it failed.
    def text(path, query = {})
      body = call(Net::HTTP::Get, path, query, as: :text, accept: "text/plain")
      body.bytesize > TEXT_LIMIT ? body.byteslice(-TEXT_LIMIT, TEXT_LIMIT).scrub : body
    end

    def post(path, body = {}, query = {}) = call(Net::HTTP::Post, path, query, body: body)

    def patch(path, body = {}, query = {}) = call(Net::HTTP::Patch, path, query, body: body)

    def put(path, body = {}, query = {}) = call(Net::HTTP::Put, path, query, body: body)

    def delete(path, query = {}) = call(Net::HTTP::Delete, path, query)

    # The values of a list answer, or the answer itself when it is a list already.
    def values(answer)
      return answer if answer.is_a?(Array)

      answer.is_a?(Hash) ? Array(answer["value"]) : []
    end

    private

    def call(method, path, query, body: nil, accept: "application/json", with_status: false, as: :json)
      uri = uri_for(path, query)
      request = method.new(uri)
      request["Authorization"] = "Basic #{Base64.strict_encode64(":#{@token}")}"
      request["Accept"] = accept
      unless body.nil?
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      answer = Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON, refine: REFINE, as: as, with_status: true)
      raise Refused, "#{PROVIDER} did not accept this token. Check it is active and made for the #{@organization} organization." if answer.status == NOT_AUTHORITATIVE

      with_status ? answer : answer.body
    end

    def uri_for(path, query)
      host = path.match?(RELEASE_PATH) ? RELEASE_HOST : HOST
      uri = URI.parse("https://#{host}/#{Http.segment(@organization)}#{path}")
      pairs = { VERSION_PARAM => API_VERSION }.merge(query.compact.transform_keys(&:to_s)).flat_map do |name, value|
        Array(value).map { |each| [ name, each.to_s ] }
      end
      uri.query = URI.encode_www_form(pairs)
      uri
    end
  end
end
