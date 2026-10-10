module Integrations
  # Calls to Vercel's REST API with a workspace's own access token, for the Vercel integration. Paths, parameters and
  # answers are the ones in Vercel's OpenAPI spec (openapi.vercel.sh). Every call names the team the token acts on, by
  # id or slug, as the spec's teamId and slug parameters take it, and a token made for one team names none.
  class VercelApi
    class Error < Integrations::Error; end
    # Refused by the plan, such as a rollback past the previous production deployment on Hobby (spec, requestRollback 402).
    class PlanLimited < Error; end
    # Vercel answered that the project or webhook is not there, the one answer a re-read takes as gone.
    class NotFound < Error
      include Integrations::NotFound
    end
    # Vercel turned the request down as it stands, such as a webhook on a plan without them or past the team's limit
    # (spec, createWebhook 400 and 403).
    class Refused < Error; end

    API_ROOT = "https://api.vercel.com".freeze
    BILLING_READ_TIMEOUT = 60
    TEAM_ID = /\Ateam_/
    PROVIDER = "Vercel".freeze
    PAYMENT_REQUIRED = 402
    NOT_FOUND = 404
    REFUSED = [ 400, 403 ].freeze
    PAGE_SIZE = 100
    MAX_PAGES = 10
    # The runtime log stream ends with a row like this when Vercel stops it (vercel/vercel, packages/cli/src/util/logs.ts).
    STREAM_END = "delimiter".freeze

    def initialize(token, team = nil)
      @token = token
      @team = team.to_s.strip.presence
    end

    # Every project, as a Pages::Read, across the pages Vercel answers in one of its three list shapes (spec, getProjects).
    def projects
      Pages.read(max_pages: MAX_PAGES) do |from|
        answer = get("/v10/projects", "limit" => PAGE_SIZE, "from" => from)
        listed = answer.is_a?(Array) ? answer : Array(answer["projects"])
        [ listed, (answer.dig("pagination", "next") if answer.is_a?(Hash) && listed.size == PAGE_SIZE) ]
      end
    end

    # The cheapest call Vercel documents for checking a token, which works for every token scope (docs, rest-api/getting-started).
    def check! = get("/v10/projects", "limit" => 1)

    def project(id_or_name) = get("/v9/projects/#{segment(id_or_name)}")

    # A project's environment variables, without decrypt, so only a plain variable's value is readable and every other
    # type comes back without its value or encrypted (spec, filterProjectEnvs, GET /v10/projects/{idOrName}/env, whose
    # answer is a bare variable, { envs, pagination } or { envs, hiddenProductionEnvCount }). Answers the variables and
    # whether a page was left.
    def project_env(project_id)
      answer = get("/v10/projects/#{segment(project_id)}/env")
      return [ [ answer ], false ] if answer.is_a?(Hash) && answer.key?("key")

      [ Array(answer["envs"]), answer.dig("pagination", "next").present? ]
    end

    # Every domain of a project, as a Pages::Read, newest first, each page read until the timestamp the one before gave as
    # next (spec, getProjectDomains and Pagination).
    def project_domains(project_id)
      Pages.read(max_pages: MAX_PAGES) do |before|
        answer = get("/v9/projects/#{segment(project_id)}/domains", "limit" => PAGE_SIZE, "until" => before)
        [ Array(answer["domains"]), answer.dig("pagination", "next") ]
      end
    end

    def deployments(project_id, limit:, target: nil)
      Array(get("/v7/deployments", "projectId" => project_id, "limit" => limit, "target" => target)["deployments"])
    end

    def deployment(id_or_url) = get("/v13/deployments/#{segment(id_or_url)}")

    # A deployment's build events, newest first (spec, getDeploymentEvents).
    def deployment_events(deployment_id, limit:)
      Array(get("/v3/deployments/#{segment(deployment_id)}/events", "direction" => "backward", "limit" => limit))
    end

    def team(team_id) = get("/v2/teams/#{segment(team_id)}")

    # The teams the token can reach, each with its id, slug and name, as a Pages::Read (GET /v2/teams, "List all teams",
    # vercel.com/docs/rest-api/teams/list-all-teams, paged by passing pagination.next back as until). A Full Account token
    # reaches every team its person belongs to, a Hobby account included since Vercel made each one a team
    # (vercel.com/changelog/2024-01-account-changes), and a team token its own team.
    def teams
      Pages.read(max_pages: MAX_PAGES) do |until_at|
        answer = get("/v2/teams", { "limit" => PAGE_SIZE, "until" => until_at }.compact)
        listed = Array(answer["teams"])
        [ listed, (answer.dig("pagination", "next") if listed.size == PAGE_SIZE) ]
      end
    end

    def user = get("/v2/user")["user"] || {}

    # What the team was charged from from to before to, a day at a time (rest-api/billing, list-focus-billing-charges),
    # streamed as JSON lines in the FOCUS format: BilledCost, BillingCurrency, ChargePeriodStart, ServiceName, and Tags
    # naming the project. At most limit rows are kept, and cut says whether more were left.
    def billing_charges(from:, to:, limit:)
      uri = uri("/v1/billing/charges", "from" => from.utc.iso8601, "to" => to.utc.iso8601)
      request = Net::HTTP::Get.new(uri)
      authorize(request)
      request["Accept"] = "application/jsonl"
      rows = []
      cut = false
      catch(:enough) do
        Http.request(uri, request, error_class: Error, read_timeout: BILLING_READ_TIMEOUT) do |response|
          refuse(response.code, response.read_body) unless response.code.to_i.between?(200, 299)

          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/\A[^\n]*\n/))
              row = parse_row(line)
              next unless row

              rows << row
              next if rows.size < limit

              cut = true
              throw :enough
            end
          end
          last = parse_row(buffer) if buffer.present?
          rows << last if last
        end
      end
      [ rows, cut ]
    end

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
        Http.request(uri, request, error_class: Error, read_timeout: seconds) do |response|
          refuse(response.code, response.read_body) unless response.code.to_i.between?(200, 299)

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
      rows
    rescue Net::ReadTimeout
      rows
    end

    def rollback(project_id, deployment_id, description: nil)
      post("/v1/projects/#{segment(project_id)}/rollback/#{segment(deployment_id)}", { "description" => description.presence })
    end

    # The team's webhooks, each with its url but never its secret (spec, getWebhooks, a bare array), read only to find one
    # Firefight registered before at the same address.
    def webhooks = Array(get("/v1/webhooks"))

    # A webhook for every project in the team, answering its id and the secret it signs with (spec, createWebhook). No
    # projectIds, since Vercel sends project events only to a webhook for all of the team's projects (docs, webhooks,
    # Project Events).
    def create_webhook(url:, events:)
      uri = uri("/v1/webhooks")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = { "url" => url, "events" => events }.to_json
      send_request(uri, request)
    end

    def delete_webhook(webhook_id)
      uri = uri("/v1/webhooks/#{segment(webhook_id)}")
      send_request(uri, Net::HTTP::Delete.new(uri))
    end

    # A promotion is queued (202) behind a rolling release in progress, or done (201), so it answers its status too.
    def promote(project_id, deployment_id)
      uri = uri("/v10/projects/#{segment(project_id)}/promote/#{segment(deployment_id)}")
      request = changing(Net::HTTP::Post.new(uri))
      authorize(request)
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: method(:refined), with_status: true)
    end

    # Any GET of the REST API, by its path under API_ROOT, for the general read (Integrations::ApiReads), which checks the
    # path before it gets here. The team is always the one this client was made for, whatever the query names.
    def read(path, query) = get(path, query.except("teamId", "slug"))

    private

    def get(path, query = {})
      uri = uri(path, query)
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def post(path, query = {})
      uri = uri(path, query)
      send_request(uri, changing(Net::HTTP::Post.new(uri)))
    end

    def changing(request)
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"
      request.body = "{}"
      request
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
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: method(:refined))
    end

    # A streamed answer that is not a 2xx, said in the same words Http.json uses (docs, rest-api/errors).
    def refuse(code, body)
      reason = (parse_row(body.to_s) || {}).dig("error", "message").presence || "no reason given"
      error = code.to_i == Http::TOO_MANY_REQUESTS ? Error.new("Vercel answered #{code}: #{reason}").extend(Integrations::RateLimited) : refined(code, reason).new("Vercel answered #{code}: #{reason}")
      raise error
    end

    def refined(code, _reason)
      case code.to_i
      when PAYMENT_REQUIRED then PlanLimited
      when NOT_FOUND then NotFound
      when *REFUSED then Refused
      else Error
      end
    end

    def parse_row(line)
      row = JSON.parse(line)
      row.is_a?(Hash) ? row : nil
    rescue JSON::ParserError
      nil
    end

    def segment(value) = Http.segment(value)
  end
end
