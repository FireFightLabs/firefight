module Integrations
  # Calls to Supabase's Management API (api.supabase.com/v1) for what its MCP server has no tool for, with the Supabase
  # connection's own credentials, a personal access token or a sign-in, both sent as Bearer as the server sends them.
  # Paths, parameters and fields are the ones in the Management API's OpenAPI description (api.supabase.com/api/v1-json).
  class SupabaseApi
    class Error < Integrations::Error; end
    class NotFound < Error
      include Integrations::NotFound
    end
    # Supabase turned the request down for what the token may do or what the project allows, as opposed to failing.
    class Refused < Error; end
    REFINED = { 400 => Refused, 401 => Refused, 403 => Refused, 404 => NotFound, 422 => Refused }.freeze

    API_ROOT = "https://api.supabase.com/v1".freeze
    NAME = "Supabase".freeze
    # Every service the health endpoint reads (V1ServiceHealthResponse's names).
    SERVICES = %w[auth db db_postgres_user pooler realtime rest storage].freeze
    # How long the health endpoint may wait on each service, at most 10000.
    HEALTH_TIMEOUT_MS = 5_000

    def initialize(authorization)
      @authorization = authorization
    end

    # A project's status, region and database (Get project).
    def project(ref) = get("/projects/#{Http.segment(ref)}")

    # How each of a project's services stands (Gets project's service health status).
    def health(ref) = Array(get("/projects/#{Http.segment(ref)}/health", { "services" => SERVICES.join(","), "timeout_ms" => HEALTH_TIMEOUT_MS }))

    # A project's preview branches with their status and latest check run (List all database branches).
    def branches(ref) = Array(get("/projects/#{Http.segment(ref)}/branches"))

    # A branch project's action runs, the runs that clone, migrate, seed and deploy it, newest first (List all action runs).
    def action_runs(ref, limit:) = Array(get("/projects/#{Http.segment(ref)}/actions", { "limit" => limit, "offset" => 0 }))

    def action_run(ref, run_id) = get("/projects/#{Http.segment(ref)}/actions/#{Http.segment(run_id)}")

    # What an action run printed, as text (Get the logs of an action run).
    def action_run_logs(ref, run_id) = get("/projects/#{Http.segment(ref)}/actions/#{Http.segment(run_id)}/logs", {}, as: :text)

    # The project's metrics in the Prometheus text format, as they are now (Scrape a project's metrics).
    def metrics(ref) = get("/projects/#{Http.segment(ref)}/analytics/endpoints/metrics", {}, as: :text)

    # The project's backups and whether point in time recovery is on (Lists all backups).
    def backups(ref) = get("/projects/#{Http.segment(ref)}/database/backups")

    def restart(ref) = write("/projects/#{Http.segment(ref)}/restart")

    # Restores the database to a moment, in Unix seconds, with point in time recovery (Restores a PITR backup).
    def restore_to(ref, at) = write("/projects/#{Http.segment(ref)}/database/backups/restore-pitr", { "recovery_time_target_unix" => at.to_i })

    private

    def get(path, query = {}, as: :json)
      uri = URI.parse("#{API_ROOT}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri), as: as)
    end

    def write(path, body = nil)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = Net::HTTP::Post.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def send_request(uri, request, as: :json)
      request["Authorization"] = @authorization
      Http.json(uri, request, error_class: Error, provider_name: NAME, refine: ->(code, _reason) { REFINED[code] }, as: as)
    end
  end
end
