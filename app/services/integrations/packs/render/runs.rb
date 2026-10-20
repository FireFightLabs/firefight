module Integrations
  module Packs
    class Render < NativePack
      # The runs Render keeps apart from deploys: a cron job's scheduled runs, which Render keeps only as the
      # cron_job_run_started and cron_job_run_ended events of the cron job (spec, serviceEvent, no list of runs), a service's
      # one-off jobs (GET /services/{serviceId}/jobs, render.com/docs/one-off-jobs), and a workflow's task runs (GET
      # /task-runs, render.com/docs/workflows). Each is run history, and a run named by its id has a part whose log is read
      # for it alone where Render's logs can be filtered to it (GET /logs, resource a job's id, taskRun a task run's), and
      # otherwise over the time it ran.
      module Runs
        CRON_RUNS = "cron_runs".freeze
        JOB_RUNS = "job_runs".freeze
        TASK_RUNS = "task_runs".freeze
        History = Capabilities::History

        CRON_EVENTS = %w[cron_job_run_started cron_job_run_ended].freeze
        JOB_ENDED = "job_run_ended".freeze
        # Render's events default to the last hour (spec, startTime), so a cron job's runs are read from this far back,
        # one page of its run events.
        CRON_DAYS = 30
        CRON_EVENT_LIMIT = 100
        # A cron job's run statuses (spec, Cron Job Run Ended, status), a one-off job's (spec, GET
        # /services/{serviceId}/jobs, status) and a task run's (spec, GET /task-runs/{taskRunId}, status), in Firefight's
        # words. A paused task run waits on something and has not ended.
        CRON_STATUSES = { "pending" => History::QUEUED, "successful" => History::SUCCEEDED, "unsuccessful" => History::FAILED,
                          "canceled" => History::CANCELLED }.freeze
        JOB_STATUSES = { "pending" => History::QUEUED, "running" => History::RUNNING, "succeeded" => History::SUCCEEDED,
                         "failed" => History::FAILED, "canceled" => History::CANCELLED }.freeze
        TASK_STATUSES = { "pending" => History::QUEUED, "running" => History::RUNNING, "paused" => History::RUNNING,
                          "completed" => History::SUCCEEDED, "succeeded" => History::SUCCEEDED, "failed" => History::FAILED,
                          "canceled" => History::CANCELLED }.freeze
        CRON_RUN = "cron run".freeze
        ONE_OFF_JOB = "one-off job".freeze
        # Render runs one-off jobs from web services, private services, background workers and cron jobs
        # (render.com/docs/one-off-jobs).
        JOB_TYPES = [ WEB_SERVICE, PRIVATE_SERVICE, BACKGROUND_WORKER, CRON_JOB ].freeze
        COMMAND_SHOWN = 80

        def self.included(pack)
          pack.tool CRON_RUNS,
                    summary: "Lists a cron job's recent runs and how each ended.",
                    description: "A Render cron job's runs of the last #{CRON_DAYS} days, newest first, each with its status, when it " \
                                 "started and finished, how long it took and why a failed one failed, and how long finished runs usually " \
                                 "take. Name a run to read it with how to read its log",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "name" => { "type" => "string", "description" => "Only runs whose kind contains this, cron run (optional)" },
                        "run" => { "type" => "string", "description" => "Only this run, by its id (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{History::LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true

          pack.tool JOB_RUNS,
                    summary: "Lists a service's one-off jobs and how each ended.",
                    description: "A Render service's one-off jobs, newest first, each with its status, its command, when it started and " \
                                 "finished and how long it took, and how long finished ones usually take. A one-off job runs a command " \
                                 "once on a copy of the service, such as a migration. Name a job to read it with why it failed and how to read its log",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "name" => { "type" => "string", "description" => "Only runs whose kind contains this, one-off job (optional)" },
                        "run" => { "type" => "string", "description" => "Only this job, by its id, such as job-... (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many jobs (optional, #{History::LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true

          pack.tool TASK_RUNS,
                    summary: "Lists a workflow's recent task runs and how each went.",
                    description: "A Render workflow's task runs, newest first, each named by its task, with its status, when it started " \
                                 "and finished and how long it took, and how long finished ones usually take. Name a run to read it with " \
                                 "each attempt and each task it started, the error a failed one gave, and how to read each one's log",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "The workflow, by name or id, as list_resources shows it" },
                        "name" => { "type" => "string", "description" => "Only runs of tasks whose name contains this (optional)" },
                        "run" => { "type" => "string", "description" => "Only this task run, by its id (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{History::LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true
        end

        def cron_runs(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          fail! "#{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}, and only a cron job has scheduled runs." unless resource[:type] == CRON_JOB

          ended = Time.current
          events = api(environment_row).events(resource[:id], "type" => CRON_EVENTS, "startTime" => CRON_DAYS.days.ago.utc.iso8601,
                                                              "endTime" => ended.utc.iso8601, "limit" => CRON_EVENT_LIMIT)
          runs = cron_run_list(resource, events)
          limit = Capabilities::Answers.limit(arguments, History::LIMIT)
          return History.result(runs, what: resource[:name], link: link(resource), name: arguments["name"], limit: limit) if arguments["run"].blank?

          run = runs.find { |each| each.named?(arguments["run"]) } ||
                fail!("#{resource[:name]} had no run #{arguments['run']} in the last #{CRON_DAYS} days. cron_runs lists its runs.")
          History.result([ run.with(parts: [ run_part(run, "run", "resource" => resource[:id], "type" => "app") ]) ], what: resource[:name], link: link(resource))
        end

        def job_runs(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless JOB_TYPES.include?(resource[:type])
            fail! "#{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}, and Render runs one-off jobs from web services, private " \
                  "services, background workers and cron jobs."
          end
          return one_job(environment_row, resource, arguments["run"].to_s.strip) if arguments["run"].present?

          limit = Capabilities::Answers.limit(arguments, History::LIMIT)
          runs = api(environment_row).jobs(resource[:id], limit: limit).map { |job| job_run(resource, job) }
          History.result(runs, what: "the one-off jobs of #{resource[:name]}", link: link(resource), name: arguments["name"], limit: limit)
        end

        def task_runs(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          fail! "#{resource[:name]} is a #{TYPE_WORDS.fetch(resource[:type])}, and only a workflow has task runs." unless resource[:type] == WORKFLOW

          api = api(environment_row)
          tasks = task_names(api, resource)
          return one_task_run(api, resource, tasks, arguments["run"].to_s.strip) if arguments["run"].present?

          limit = Capabilities::Answers.limit(arguments, History::LIMIT)
          runs = api.task_runs(resource[:id], limit: limit).map { |run| task_run(resource, run, tasks) }
          History.result(runs, what: resource[:name], link: link(resource), name: arguments["name"], limit: limit)
        end

        private

        # A cron run from its start and end events, by the run's id. A run whose start fell before the events read is left
        # out, since when it began is not known.
        def cron_run_list(resource, events)
          events.group_by { |event| event.dig("details", "cronJobRunId") }.filter_map do |id, pair|
            started = pair.find { |event| event["type"] == CRON_EVENTS.first }
            ended = pair.find { |event| event["type"] == CRON_EVENTS.last }
            next if id.blank? || started.nil?

            details = ended&.dig("details") || {}
            by = details.dig("user", "email")
            History::Run.new(
              id: id, name: CRON_RUN, status: ended ? History.status(details["status"], CRON_STATUSES) : History::RUNNING,
              started_at: Telemetry.parse_time(started["timestamp"]), finished_at: Telemetry.parse_time(ended&.dig("timestamp")), url: resource[:url],
              detail: [ failure_words(details["reason"]), ("started by #{by}" if by.present?) ].compact.join(", ").presence
            )
          end
        end

        def job_run(resource, job, reason: nil)
          command = job["startCommand"].to_s.lines.first.to_s.strip
          History::Run.new(
            id: job["id"], name: ONE_OFF_JOB, status: History.status(job["status"], JOB_STATUSES),
            started_at: Telemetry.parse_time(job["startedAt"] || job["createdAt"]), finished_at: Telemetry.parse_time(job["finishedAt"]),
            url: resource[:url], detail: [ (command.truncate(COMMAND_SHOWN) if command.present?), reason ].compact.join(", ").presence
          )
        end

        # One job, with why it ended from its job_run_ended event, and its log read by the job's own id.
        def one_job(environment_row, resource, id)
          api = api(environment_row)
          job = begin
            api.job(resource[:id], id)
          rescue RenderApi::NotFound
            fail! "#{resource[:name]} has no one-off job #{id}. job_runs lists its jobs."
          end
          run = job_run(resource, job, reason: job_reason(api, resource, job))
          History.result([ run.with(parts: [ run_part(run, "job", "resource" => resource[:id], "job" => job["id"]) ]) ],
                         what: "the one-off jobs of #{resource[:name]}", link: link(resource))
        end

        def job_reason(api, resource, job)
          from = Telemetry.parse_time(job["createdAt"]) || Time.current
          to = Telemetry.parse_time(job["finishedAt"]) || Time.current
          events = api.events(resource[:id], "type" => [ JOB_ENDED ], "startTime" => (from - PHASE_MARGIN).utc.iso8601,
                                             "endTime" => (to + PHASE_MARGIN).utc.iso8601, "limit" => PHASE_EVENT_LIMIT)
          failure_words(events.find { |event| event.dig("details", "jobId") == job["id"] }&.dig("details", "reason"))
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error
          nil
        end

        # The workflow's tasks by id, so each run is named by its task. A list Render refuses leaves runs named by task id.
        def task_names(api, resource)
          api.tasks(resource[:id]).items.to_h { |task| [ task["id"], task["name"].presence || task["id"] ] }
        rescue Integrations::RateLimited
          raise
        rescue RenderApi::Error
          {}
        end

        def task_run(resource, run, tasks)
          retries = run["retries"].to_i
          History::Run.new(
            id: run["id"], name: tasks.fetch(run["taskId"], run["taskId"]), status: History.status(run["status"], TASK_STATUSES),
            started_at: Telemetry.parse_time(run["startedAt"]), finished_at: Telemetry.parse_time(run["completedAt"]), url: resource[:url],
            detail: [ run["error"].presence, ("retried #{retries} #{'time'.pluralize(retries)}" if retries.positive?),
                      ("started by task run #{run['parentTaskRunId']}" if run["parentTaskRunId"].present? && run["parentTaskRunId"] != run["id"]) ].compact.join(", ").presence
          )
        end

        # One task run with each attempt and each task run it started, each read in the workflow's log for that run alone. A
        # run of another workflow's task is refused.
        def one_task_run(api, resource, tasks, id)
          found = begin
            api.task_run(id)
          rescue RenderApi::NotFound
            fail! "#{resource[:name]} has no task run #{id}. task_runs lists its runs."
          end
          fail! "Task run #{id} belongs to another workflow, not #{resource[:name]}." if tasks.any? && !tasks.key?(found["taskId"])

          run = task_run(resource, found, tasks)
          attempts = Array(found["attempts"]).map do |attempt|
            part = History::Part.new(
              id: "attempt-#{attempt['attempt']}", name: "attempt #{attempt['attempt'].to_i + 1}", status: History.status(attempt["status"], TASK_STATUSES),
              started_at: Telemetry.parse_time(attempt["startedAt"]), finished_at: Telemetry.parse_time(attempt["completedAt"]), url: resource[:url],
              detail: attempt["error"].presence
            )
            part.with(log: log_ref(part, "resource" => resource[:id], "task_run" => found["id"]))
          end
          children = api.child_task_runs(found["id"]).reject { |child| child["id"] == found["id"] }.map do |child|
            sub = task_run(resource, child, tasks)
            part = History::Part.new(id: sub.id, name: "#{sub.name} (task run #{sub.id})", status: sub.status, started_at: sub.started_at,
                                     finished_at: sub.finished_at, url: resource[:url], detail: child["error"].presence)
            part.with(log: log_ref(part, "resource" => resource[:id], "task_run" => child["id"]))
          end
          History.result([ run.with(parts: attempts + children) ], what: resource[:name], link: link(resource))
        end

        def run_part(run, name, arguments)
          part = History::Part.new(id: run.id, name: name, status: run.status, started_at: run.started_at, finished_at: run.finished_at,
                                   url: run.url, detail: run.detail)
          part.with(log: log_ref(part, arguments))
        end

        # How a part's log is read: search_logs over the time it ran, a little past its end, as Render stamps lines on its
        # own clock.
        def log_ref(part, arguments)
          window = { "start" => part.started_at&.utc&.iso8601, "end" => (part.finished_at && (part.finished_at + PHASE_MARGIN).utc.iso8601) }
          { History::LOG_TOOL => "search_logs", History::LOG_ARGUMENTS => arguments.merge(window).compact }
        end
      end
    end
  end
end
