module Integrations
  # Calls to Vercel's REST API with a workspace's own access token, for the Vercel integration. Paths, parameters and
  # answers are the ones in Vercel's OpenAPI spec (openapi.vercel.sh). Every call names the team the token acts on, by
  # id or slug, as the spec's teamId and slug parameters take it, and a token made for one team names none.
  class VercelApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error; end
    # Refused by the plan, such as a rollback past the previous production deployment on Hobby (spec, requestRollback 402).
    class PlanLimited < Error; end

    API_ROOT = "https://api.vercel.com".freeze
    TEAM_ID = /\Ateam_/
    TOO_MANY_REQUESTS = 429
    PAYMENT_REQUIRED = 402
    PAGE_SIZE = 100
    MAX_PAGES = 10
    # The runtime log stream ends with a row like this when Vercel stops it (vercel/vercel, packages/cli/src/util/logs.ts).
    STREAM_END = "delimiter".freeze

    # What a change answered, with its HTTP status as well as its body, since a promotion can be queued (202) rather
    # than done (201).
    Answer = Data.define(:status, :body)

    def initialize(token, team = nil)
      @token = token
      @team = team.to_s.strip.presence
    end

    # Every project, across the pages Vercel answers in one of its three list shapes (spec, getProjects).
    def projects
      rows = []
      from = nil
      MAX_PAGES.times do
        answer = get("/v10/projects", "limit" => PAGE_SIZE, "from" => from)
        listed = answer.is_a?(Array) ? answer : Array(answer["projects"])
        rows.concat(listed)
        from = answer.is_a?(Hash) ? answer.dig("pagination", "next") : nil
        break if from.blank? || listed.size < PAGE_SIZE
      end
      rows
    end

    # The cheapest call Vercel documents for checking a token, which works for every token scope (docs, rest-api/getting-started).
    def check! = get("/v10/projects", "limit" => 1)

    def project(id_or_name) = get("/v9/projects/#{segment(id_or_name)}")

    def project_domains(project_id) = Array(get("/v9/projects/#{segment(project_id)}/domains", "limit" => PAGE_SIZE)["domains"])

    def deployments(project_id, limit:, target: nil)
      Array(get("/v7/deployments", "projectId" => project_id, "limit" => limit, "target" => target)["deployments"])
    end

    def deployment(id_or_url) = get("/v13/deployments/#{segment(id_or_url)}")

    # A deployment's build events, newest first (spec, getDeploymentEvents).
    def deployment_events(deployment_id, limit:)
      Array(get("/v3/deployments/#{segment(deployment_id)}/events", "direction" => "backward", "limit" => limit))
    end

    def team(team_id) = get("/v2/teams/#{segment(team_id)}")

    def user = get("/v2/user")["user"] || {}

    # What a deployment logs while it is watched, for at most seconds or limit rows. The endpoint streams live rows as
    # NDJSON and takes no time range (spec, getRuntimeLogs), so nothing from before the call comes back.
    def runtime_logs(project_id, deployment_id, seconds:, limit:)
      uri = uri("/v1/projects/#{segment(project_id)}/deployments/#{segment(deployment_id)}/runtime-logs")
      request = Net::HTTP::Get.new(uri)
      authorize(request)
      request["Accept"] = "application/stream+json"
      rows = []
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
      catch(:enough) do
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: Http::OPEN_TIMEOUT, read_timeout: seconds) do |connection|
          connection.request(request) do |response|
            raise_for(response.code, response.read_body) unless response.code.to_i.between?(200, 299)

            buffer = +""
            response.read_body do |chunk|
              buffer << chunk
              while (line = buffer.slice!(/\A[^\n]*\n/))
                row = parse_row(line)
                throw :enough if row && row["source"] == STREAM_END && row["rowId"].to_s.empty?
                rows << row if row
                throw :enough if rows.size >= limit
              end
              throw :enough if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            end
          end
        end
      end
      rows
    rescue Net::ReadTimeout
      rows
    rescue Timeout::Error, SystemCallError, SocketError, OpenSSL::SSL::SSLError => error
      raise Error, "could not reach #{uri.host} (#{error.class.name})"
    end

    def rollback(project_id, deployment_id, description: nil)
      post("/v1/projects/#{segment(project_id)}/rollback/#{segment(deployment_id)}", { "description" => description.presence })
    end

    def promote(project_id, deployment_id) = post("/v10/projects/#{segment(project_id)}/promote/#{segment(deployment_id)}")

    private

    def get(path, query = {})
      uri = uri(path, query)
      request = Net::HTTP::Get.new(uri)
      send_request(uri, request).body
    end

    def post(path, query = {})
      uri = uri(path, query)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = "{}"
      send_request(uri, request)
    end

    def uri(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      team = if @team.nil? then {}
      elsif @team.match?(TEAM_ID) then { "teamId" => @team }
      else { "slug" => @team }
      end
      pairs = query.merge(team).compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      uri
    end

    def authorize(request)
      request["Authorization"] = "Bearer #{@token}"
    end

    def send_request(uri, request)
      authorize(request)
      request["Accept"] ||= "application/json"
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      raise_for(response.code, response.body) unless response.code.to_i.between?(200, 299)

      Answer.new(status: response.code.to_i, body: response.body.to_s.strip.empty? ? {} : JSON.parse(response.body))
    rescue JSON::ParserError
      # A change that went through stays one that went through, whatever came back with it.
      Answer.new(status: response.code.to_i, body: {})
    end

    # Vercel's error body is { error: { code, message } } (docs, rest-api/errors).
    def raise_for(code, body)
      parsed = parse_row(body.to_s) || {}
      reason = parsed.dig("error", "message").presence || "no reason given"
      error = case code.to_i
      when TOO_MANY_REQUESTS then RateLimited
      when PAYMENT_REQUIRED then PlanLimited
      else Error
      end
      raise error, "Vercel answered #{code}: #{reason}"
    end

    def parse_row(line)
      row = JSON.parse(line)
      row.is_a?(Hash) ? row : nil
    rescue JSON::ParserError
      nil
    end

    def segment(value) = ERB::Util.url_encode(value.to_s)
  end
end
