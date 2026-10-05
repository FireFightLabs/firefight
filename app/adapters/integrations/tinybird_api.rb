module Integrations
  # Calls to Tinybird's API with a workspace's own token, for the Tinybird integration. Every call reads. The paths,
  # parameters and answers are from Tinybird's API reference (tinybird.co/docs/api-reference: the Data Sources, Pipes and
  # Query APIs), and the workspace a token belongs to from GET /v1/workspace, which Tinybird's own TypeScript SDK reads
  # (tinybirdco/tinybird-sdk-typescript, src/api/workspaces.ts). A workspace lives in one region, each with its own API
  # host from the reference's table of regions, named by the registry's region keys. The token goes as a Bearer header,
  # as the reference's section on authentication shows.
  class TinybirdApi
    class Error < Integrations::Error; end
    # The token is wrong, or its scopes do not reach what was read.
    class Refused < Error; end

    HOSTS = {
      "gcp-europe-west3" => "https://api.tinybird.co",
      "gcp-europe-west2" => "https://api.europe-west2.gcp.tinybird.co",
      "gcp-us-east4" => "https://api.us-east.tinybird.co",
      "gcp-northamerica-northeast2" => "https://api.northamerica-northeast2.gcp.tinybird.co",
      "aws-eu-central-1" => "https://api.eu-central-1.aws.tinybird.co",
      "aws-eu-west-1" => "https://api.eu-west-1.aws.tinybird.co",
      "aws-us-east-1" => "https://api.us-east.aws.tinybird.co",
      "aws-us-west-2" => "https://api.us-west-2.aws.tinybird.co",
      "aws-ap-east-1" => "https://api.ap-east-1.aws.tinybird.co",
      "aws-ap-southeast-2" => "https://api.ap-southeast-2.aws.tinybird.co"
    }.freeze
    DEFAULT_REGION = "gcp-europe-west3".freeze
    REFUSALS = [ 401, 403 ].freeze
    # A query or an endpoint call can take longer than a list, so it is given a minute.
    QUERY_TIMEOUT = 60
    REDACTED = "[REDACTED:tinybird_token]".freeze

    # region is the registry's region key. A connection that names none reaches Tinybird's default region.
    def initialize(token, region: nil)
      @token = token
      @root = HOSTS.fetch(region.presence || DEFAULT_REGION) { raise Error, "Tinybird has no #{region} region" }
    end

    # The workspace the token belongs to: its id and name.
    def workspace = get("/v1/workspace")

    # Every data source the token can read, with its engine, statistics and the pipes that use it.
    def datasources = Array(get("/v0/datasources")["datasources"])

    def datasource(name) = get("/v0/datasources/#{Http.segment(name)}")

    # Every pipe the token can read, with its nodes and, for an endpoint, the node it publishes. dependencies adds what
    # each node reads.
    def pipes = Array(get("/v0/pipes", { "dependencies" => "true" })["pipes"])

    def pipe(name) = get("/v0/pipes/#{Http.segment(name)}")

    # A query through the Query API, which only reads, answered in Tinybird's JSON format: meta, data, rows and
    # statistics. The query is sent in the body, so a long one fits.
    def query(sql)
      uri = URI.parse("#{@root}/v0/sql")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { "q" => "#{sql} FORMAT JSON" }.to_json
      send_request(uri, request, read_timeout: QUERY_TIMEOUT)
    end

    # A published endpoint's answer for the parameters given, in the JSON format.
    def call_endpoint(name, params)
      get("/v0/pipes/#{Http.segment(name)}.json", params.to_h.transform_values(&:to_s), read_timeout: QUERY_TIMEOUT)
    end

    private

    def get(path, query = {}, read_timeout: 30)
      uri = URI.parse("#{@root}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri), read_timeout: read_timeout)
    end

    # Tinybird's refusal of a token can quote the token back, so it is taken out of the words before anyone reads them.
    def send_request(uri, request, read_timeout:)
      request["Authorization"] = "Bearer #{@token}"
      Http.json(uri, request, error_class: Error, provider_name: "Tinybird", read_timeout: read_timeout,
                              refine: ->(code, _said) { Refused if REFUSALS.include?(code) })
    rescue Error => error
      raise unless @token.present? && error.message.include?(@token)

      scrubbed = error.class.new(error.message.gsub(@token, REDACTED))
      scrubbed.extend(RateLimited) if error.is_a?(RateLimited)
      raise scrubbed
    end
  end
end
