module Integrations
  # Calls to GitLab's REST API (v4) with a workspace's own access token, on GitLab.com or the workspace's own GitLab.
  # Paths, parameters and fields are GitLab's, from doc/api in gitlab-org/gitlab. A host other than GitLab.com is
  # reached only on a public address unless an operator allowed it, and every call goes to the address checked first.
  class GitlabApi
    class Error < Integrations::Error; end
    class NotFound < Error; end
    # The token is not accepted, or may not do this.
    class Refused < Error; end

    DEFAULT_URL = "https://gitlab.com".freeze
    API_PATH = "/api/v4".freeze
    TOKEN_HEADER = "PRIVATE-TOKEN".freeze
    PROVIDER_KEY = "gitlab".freeze
    PROVIDER = "GitLab".freeze
    PAGE_SIZE = 100
    NEXT_PAGE = "x-next-page".freeze
    # GitLab's codes that say more than that the call failed.
    REFINED = { 401 => Refused, 403 => Refused, 404 => NotFound }.freeze
    REFINE = ->(code, _reason) { REFINED[code] }
    # A job log can be long, and only its end usually says why it failed.
    TEXT_LIMIT = 2_000_000

    attr_reader :base_url

    # base_url is where the GitLab instance is, GitLab.com when blank, and may carry a path when it is served under one.
    def self.base_url(value)
      url = value.to_s.strip.delete_suffix("/")
      return DEFAULT_URL if url.empty?

      uri = URI.parse(url)
      raise Error, "The GitLab address must start with https://." unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise Error, "The GitLab address is only the instance's address, without a query or credentials." if uri.query || uri.userinfo || uri.fragment

      url.delete_suffix(API_PATH)
    rescue URI::InvalidURIError
      raise Error, "#{value} is not a web address."
    end

    def initialize(base_url, token)
      @base_url = self.class.base_url(base_url)
      @token = token
      @host = URI.parse(@base_url).host
    end

    # A project's path in the API, where its groups and name are one encoded segment.
    def self.project(path) = "/projects/#{Http.segment(path)}"

    def self.file(project_path, file_path) = "#{project(project_path)}/repository/files/#{Http.segment(file_path)}"

    def get(path, query = {}) = call(api_uri(path, query))

    # A change, such as running or retrying a pipeline, with its attributes as a JSON body, which the API takes as it
    # takes them in the query (doc/api/rest, request payload).
    def post(path, body = {}) = changing(Net::HTTP::Post, path, body)

    def put(path, body = {}) = changing(Net::HTTP::Put, path, body)

    # An answer with no body, as deleting a webhook's 204, reads as {}.
    def delete(path)
      uri = api_uri(path, {})
      call(uri, request: Net::HTTP::Delete.new(uri))
    end

    # Every page of a list, up to pages of PAGE_SIZE, following GitLab's x-next-page header. Returns the items and
    # whether more were left.
    def list(path, query = {}, pages: 1)
      read = Pages.read(max_pages: pages) do |page|
        answer = call(api_uri(path, query.merge("per_page" => PAGE_SIZE, "page" => page || 1)), with_status: true)
        [ answer.body, answer.header(NEXT_PAGE).to_s ]
      end
      [ read.items, read.incomplete? ]
    end

    # Plain text, such as a job's log or a raw file, cut to TEXT_LIMIT from the end, where a job says why it failed.
    def text(path, query = {})
      body = call(api_uri(path, query), as: :text)
      body.bytesize > TEXT_LIMIT ? body.byteslice(-TEXT_LIMIT, TEXT_LIMIT).scrub : body
    end

    def web_url(*segments) = [ @base_url, *segments ].join("/")

    # The address a host other than GitLab.com was checked at, or nil for GitLab.com.
    def address = address_of(@host)

    # A file's headers only, such as its size, without reading it, as an Http::Answer.
    def head(path, query = {})
      uri = api_uri(path, query)
      call(uri, request: Net::HTTP::Head.new(uri), with_status: true)
    end

    private

    def changing(method, path, body)
      uri = api_uri(path, {})
      request = method.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      call(uri, request: request)
    end

    def api_uri(path, query)
      uri = URI.parse("#{@base_url}#{API_PATH}#{path}")
      uri.query = encode(query) if query.any?
      uri
    end

    def call(uri, request: Net::HTTP::Get.new(uri), **)
      request[TOKEN_HEADER] = @token
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: REFINE, ipaddr: address, **)
    end

    # GitLab.com is GitLab's own, so only another host is checked.
    def address_of(host)
      return nil if host == URI.parse(DEFAULT_URL).host

      PublicAddress.check!(host, provider_key: PROVIDER_KEY).ip.to_s
    rescue PublicAddress::Refused => error
      raise Error, error.message
    end

    # A list such as scope[] is sent once per value, as GitLab reads arrays.
    def encode(query)
      pairs = query.compact.flat_map do |name, value|
        value.is_a?(Array) ? value.map { |each| [ "#{name}[]", each.to_s ] } : [ [ name.to_s, value.to_s ] ]
      end
      URI.encode_www_form(pairs)
    end
  end
end
