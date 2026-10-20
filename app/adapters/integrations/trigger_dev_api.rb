module Integrations
  # Calls to Trigger.dev's management API with one environment's secret API key, for the Trigger.dev integration. The
  # key belongs to one project environment, so every call reads or changes that environment only. Paths, parameters and
  # answers are the ones in Trigger.dev's OpenAPI spec (triggerdotdev/trigger.dev, docs/v3-openapi.yaml).
  class TriggerDevApi
    class Error < Integrations::Error; end
    PROVIDER = "Trigger.dev".freeze

    API_ROOT = "https://api.trigger.dev".freeze
    # Lists come a page at a time, at most this many to a page, and a list never reads past MAX_PAGES.
    PAGE_SIZE = 100
    MAX_PAGES = 5
    # Deployments are listed at least five to a page (list_deployments_v1).
    MIN_DEPLOYMENT_PAGE = 5
    # Runs are listed at least ten to a page (list_runs_v1).
    MIN_RUN_PAGE = 10

    def initialize(key)
      @key = key
    end

    # Runs newest first. filter uses the spec's own names (taskIdentifier, status, createdAt with from, to or period),
    # each sent as filter[name], a list as one comma separated value.
    def runs(filter: {}, limit: PAGE_SIZE)
      paged("/api/v1/runs", deep("filter", filter), limit, MIN_RUN_PAGE)
    end

    def run(run_id) = get("/api/v3/runs/#{segment(run_id)}")

    # What a run logged and the spans it went through (get_run_events_v1).
    def run_events(run_id) = Array(get("/api/v1/runs/#{segment(run_id)}/events")["events"])

    def deployments(status: nil, limit: 20)
      paged("/api/v1/deployments", { "status" => status }.compact, limit, MIN_DEPLOYMENT_PAGE)
    end

    def deployment(deployment_id) = get("/api/v1/deployments/#{segment(deployment_id)}")

    # The environment's variables as name, value and isSecret, a secret's value redacted. environment is the slug the key
    # belongs to (dev, stg, prod or preview), and a key of another environment is refused.
    # https://github.com/triggerdotdev/trigger.dev/blob/main/apps/webapp/app/routes/api.v1.projects.$projectRef.envvars.$slug.ts
    def environment_variables(project, environment) = Array(get("/api/v1/projects/#{segment(project)}/envvars/#{segment(environment)}"))

    # Error groups with how often each happened in the range (list_errors_v1).
    def errors(filter: {}, limit: PAGE_SIZE) = paged("/api/v1/errors", deep("filter", filter), limit, 1)

    # Queues and concurrency limits use page numbers rather than a cursor (list_queues_v1, list_concurrency_limits_v1).
    def queues = numbered("/api/v1/queues")

    def concurrency_limits = numbered("/api/v1/concurrency-limits")

    # A TRQL query over the environment's runs or metrics, for the time between from and to (execute_query_v1). The time
    # range is sent beside the query, as Trigger.dev's query docs recommend, rather than written into it.
    def query(trql, from:, to:)
      body = { "query" => trql, "scope" => "environment", "from" => from.utc.iso8601, "to" => to.utc.iso8601, "format" => "json" }
      Array(post("/api/v1/query", body)["results"])
    end

    # Makes an earlier deployed version the one new runs start on (promote_deployment_v1).
    def promote(version) = post("/api/v1/deployments/#{segment(version)}/promote", nil)

    # Cancels a run still going, and does nothing to one already finished (cancel_run_v1).
    def cancel_run(run_id) = post("/api/v2/runs/#{segment(run_id)}/cancel", nil)

    # A new run with the same payload and options as the one named, in the same environment, answering the new run's id
    # (replay_run_v1). An empty body replays it unchanged.
    def replay_run(run_id) = post("/api/v1/runs/#{segment(run_id)}/replay", {})

    # Cancels or replays many runs at once, by their ids or by a filter, answering the bulk action's id
    # (create_bulk_action_v1). It runs on Trigger.dev's side after the answer.
    def bulk_action(action, name:, run_ids: nil, filter: nil)
      post("/api/v1/bulk-actions", { "action" => action, "name" => name, "runIds" => run_ids, "filter" => filter }.compact)
    end

    # One bulk action with its status and counts (retrieve_bulk_action_v1), and aborting one still pending, which stops it
    # taking more runs and undoes none already done (abort_bulk_action_v1).
    def bulk_action_status(bulk_id) = get("/api/v1/bulk-actions/#{segment(bulk_id)}")

    def abort_bulk_action(bulk_id) = post("/api/v1/bulk-actions/#{segment(bulk_id)}/abort", nil)

    # One queue by its id, or by a task's identifier or a custom queue's name with type (retrieve_queue_v1).
    def queue(name, type) = get("/api/v1/queues/#{segment(name)}", { "type" => type })

    # Pauses a queue, so no new run starts, or resumes it (pause_queue_v1). action is pause or resume.
    def pause_queue(name, type, action) = post("/api/v1/queues/#{segment(name)}/pause", { "type" => type, "action" => action })

    def override_queue_concurrency(name, type, limit)
      post("/api/v1/queues/#{segment(name)}/concurrency/override", { "type" => type, "concurrencyLimit" => limit })
    end

    # Puts a queue's limit back to the one its code declares (reset_queue_concurrency_v1).
    def reset_queue_concurrency(name, type) = post("/api/v1/queues/#{segment(name)}/concurrency/reset", { "type" => type })

    def concurrency_limit(name) = get("/api/v1/concurrency-limits/#{segment(name)}")

    def pause_concurrency_limit(name, action) = post("/api/v1/concurrency-limits/#{segment(name)}/pause", { "action" => action })

    # Overrides a concurrency limit's total, its per key bound or both, keeping the declared values for reset
    # (override_concurrency_limit_v1).
    def override_concurrency_limit(name, total: nil, per_key: nil)
      post("/api/v1/concurrency-limits/#{segment(name)}/override", { "total" => total, "perKey" => per_key }.compact)
    end

    def reset_concurrency_limit(name) = post("/api/v1/concurrency-limits/#{segment(name)}/reset", {})

    # One error group with its status (retrieve_error_v1).
    def error_group(error_id) = get("/api/v1/errors/#{segment(error_id)}")

    # Marks an error group resolved, in a version when named (resolve_error_v1).
    def resolve_error(error_id, version: nil) = post("/api/v1/errors/#{segment(error_id)}/resolve", { "resolvedInVersion" => version }.compact)

    # Marks an error group ignored, for a while or until it happens more than a rate or a count when given (ignore_error_v1).
    def ignore_error(error_id, duration_ms: nil, occurrence_rate: nil, total_occurrences: nil, reason: nil)
      body = { "duration" => duration_ms, "occurrenceRate" => occurrence_rate, "totalOccurrences" => total_occurrences, "reason" => reason }.compact
      post("/api/v1/errors/#{segment(error_id)}/ignore", body)
    end

    # Moves a resolved or ignored error group back to unresolved (unresolve_error_v1).
    def unresolve_error(error_id) = post("/api/v1/errors/#{segment(error_id)}/unresolve", nil)

    # Any GET of the API by its path, /api/v1 and the rest included, for the general read (Integrations::ApiReads),
    # which checks the path before it gets here.
    def read(path, query) = get(path, query)

    private

    # Every page up to limit, following pagination.next as page[after].
    def paged(path, query, limit, minimum)
      size = limit.clamp(minimum, PAGE_SIZE)
      found = []
      after = nil
      MAX_PAGES.times do
        body = get(path, query.merge("page[size]" => size, "page[after]" => after).compact)
        found.concat(Array(body["data"]))
        after = body.dig("pagination", "next")
        break if after.blank? || found.size >= limit
      end
      found.first(limit)
    end

    # Every page up to MAX_PAGES, as a Pages::Read that says whether the list was cut short.
    def numbered(path)
      Pages.read(max_pages: MAX_PAGES) do |page|
        page ||= 1
        body = get(path, "page" => page, "perPage" => PAGE_SIZE)
        [ Array(body["data"]), (page + 1 if page < body.dig("pagination", "totalPages").to_i) ]
      end
    end

    # A filter object in the spec's deepObject style, filter[createdAt][from] for a nested field.
    def deep(name, value)
      value.compact.each_with_object({}) do |(key, inner), query|
        if inner.is_a?(Hash)
          query.merge!(deep("#{name}[#{key}]", inner))
        elsif inner.present?
          query["#{name}[#{key}]"] = Array(inner).join(",")
        end
      end
    end

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def post(path, body)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json if body
      send_request(uri, request)
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@key}"
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER)
    end

    def segment(value) = Http.segment(value)
  end
end
