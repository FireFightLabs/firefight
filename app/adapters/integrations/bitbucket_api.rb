module Integrations
  # Calls to Bitbucket Cloud's REST API (2.0) with a workspace's own token, sent as a bearer token, which Bitbucket takes
  # for an API token and for a workspace, project or repository access token. Paths, parameters and fields are from
  # Bitbucket's OpenAPI description (api.bitbucket.org/swagger.json). A list is paged by following its next address.
  class BitbucketApi
    class Error < Integrations::Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # The token is not accepted, or may not do this.
    class Refused < Error; end

    API_ROOT = "https://api.bitbucket.org/2.0".freeze
    HOST = "api.bitbucket.org".freeze
    PROVIDER_KEY = "bitbucket".freeze
    PROVIDER = "Bitbucket".freeze
    PAGE_SIZE = 100
    # A step's log can be long, and only its end usually says why it failed.
    TEXT_LIMIT = 2_000_000
    # Bitbucket's codes that say more than that the call failed.
    REFINED = { 401 => Refused, 403 => Refused, 404 => NotFound }.freeze
    REFINE = ->(code, _reason) { REFINED[code] }

    def initialize(token)
      @token = token
    end

    # A repository's path in the API, its workspace and slug each one encoded segment.
    def self.repository(full_name)
      workspace, slug = full_name.to_s.split("/", 2)
      "/repositories/#{Http.segment(workspace)}/#{Http.segment(slug)}"
    end

    # A path inside a repository, each segment encoded, so a space or a hash in a name still reaches the file.
    def self.path(value) = value.to_s.split("/").map { |part| Http.segment(part) }.join("/")

    def get(path, query = {}) = json(api_uri(path, query))

    # Any GET of the API, by its path after /2.0, for the general read (Integrations::ApiReads), which checks the path
    # before it gets here. A list value is sent once per value.
    def read(path, query)
      uri = URI.parse("#{API_ROOT}#{path}")
      pairs = query.flat_map { |name, value| Array(value).map { |each| [ name, each ] } }
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      json(uri)
    end

    # A change, such as running or stopping a pipeline. An answer with no body, as stopPipeline's 204, reads as {}.
    def post(path, body = nil) = changing(Net::HTTP::Post, path, body)

    def put(path, body) = changing(Net::HTTP::Put, path, body)

    def delete(path)
      uri = api_uri(path, {})
      Http.json(uri, authorized(Net::HTTP::Delete.new(uri)), error_class: Error, provider_name: PROVIDER, refine: REFINE)
    end

    # Every page of a list, following next, up to pages. Returns the items and whether more were left.
    def list(path, query = {}, pages: 1)
      first = api_uri(path, { "pagelen" => PAGE_SIZE }.merge(query))
      read = Pages.read(max_pages: pages) do |following|
        uri = following ? URI.parse(following) : first
        raise Error, "Bitbucket's next page is not on its API." unless uri.is_a?(URI::HTTPS) && uri.host == HOST

        body = json(uri)
        [ body["values"], body["next"].to_s ]
      end
      [ read.items, read.incomplete? ]
    end

    # Plain text, such as a step's log, a diff or a raw file, cut to TEXT_LIMIT from the end, where a step says why it
    # failed. A finished step's log answers with a redirect to where it is kept (Bitbucket's OpenAPI description, the
    # step log path), followed without the token.
    def text(path, query = {})
      body = json(api_uri(path, query), as: :text, redirect: :download, provider_key: PROVIDER_KEY, download_limit: TEXT_LIMIT)
      body.bytesize > TEXT_LIMIT ? body.byteslice(-TEXT_LIMIT, TEXT_LIMIT).scrub : body
    end

    private

    def changing(method, path, body)
      uri = api_uri(path, {})
      request = authorized(method.new(uri))
      unless body.nil?
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: REFINE)
    end

    def api_uri(path, query)
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = URI.encode_www_form(query.compact.transform_values(&:to_s)) if query.compact.any?
      uri
    end

    def authorized(request)
      request["Authorization"] = "Bearer #{@token}"
      request
    end

    def json(uri, **) = Http.json(uri, authorized(Net::HTTP::Get.new(uri)), error_class: Error, provider_name: PROVIDER, refine: REFINE, **)
  end
end
