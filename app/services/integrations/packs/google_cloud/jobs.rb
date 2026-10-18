module Integrations
  module Packs
    class GoogleCloud < NativePack
      # Cloud Run jobs and their executions, from Cloud Run Admin API v2 (Job, Execution, Task and Condition). An execution
      # is one run of the job, made of tasks that each run the job's container to its end and are retried up to their
      # limit. Each execution and task gives the address of its own logs in the console (logUri), and Cloud Logging
      # labels a job's lines with the execution and task index they came from (Cloud Run, Logging and viewing logs).
      module Jobs
        LIST_EXECUTIONS = "list_executions".freeze
        EXECUTION_LIMIT = 20
        History = Capabilities::History
        COMPLETED = "Completed".freeze
        # The job's last execution as the map shows it, from ExecutionReference.completionStatus.
        COMPLETION_WORDS = {
          "EXECUTION_SUCCEEDED" => "completed", "EXECUTION_FAILED" => "failed", "EXECUTION_RUNNING" => "running",
          "EXECUTION_PENDING" => "pending", "EXECUTION_CANCELLED" => "stopped"
        }.freeze
        CONDITION_STATES = {
          "condition_succeeded" => History::SUCCEEDED, "condition_failed" => History::FAILED,
          "condition_pending" => History::QUEUED, "condition_reconciling" => History::RUNNING
        }.freeze
        # Condition.executionReason for a run someone stopped, and for one being stopped.
        CANCELLED = "CANCELLED".freeze
        CANCELLING = "CANCELLING".freeze
        JOB_LOG = "cloud_run_job".freeze
        EXECUTION_LABEL = "run.googleapis.com/execution_name".freeze
        TASK_LABEL = "run.googleapis.com/task_index".freeze

        def self.included(pack)
          pack.tool LIST_EXECUTIONS,
                    summary: "Lists a Cloud Run job's recent executions with their status, timing and task results.",
                    description: "A Cloud Run job's recent executions, newest first, each with its status, when it started and finished, " \
                                 "how long it took, how many of its tasks succeeded, failed or were retried, and how long finished " \
                                 "executions usually take. Name an execution to read it with each task, how each ended, its exit code " \
                                 "and why it failed",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "A Cloud Run job, by name or id, as list_resources shows it" },
                        "run" => { "type" => "string", "description" => "Only this execution, by its name, with each of its tasks (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many executions (optional, #{EXECUTION_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true
        end

        def list_executions(environment_row:, arguments:)
          target = job_target(environment_row, arguments["resource"])
          what = "the executions of #{target.name}"
          link = page_link(environment_row, target.project, TYPE_JOB)
          if arguments["run"].present?
            execution = execution_of(environment_row, target, arguments["run"])
            tasks = api(environment_row).execution_tasks(target.project, target.location, target.name, short(execution["name"])).items
            run = execution_run(execution, target).with(parts: task_parts(target, execution, tasks))
            return History.result([ run ], what: what, link: link)
          end

          limit = Capabilities::Answers.limit(arguments, EXECUTION_LIMIT)
          read = api(environment_row).job_executions(target.project, target.location, target.name)
          newest = read.items.sort_by { |execution| execution["createTime"].to_s }.reverse.first(limit)
          result = History.result(newest.map { |execution| execution_run(execution, target) }, what: what, link: link, limit: limit)
          return result if read.complete

          note = "Cloud Run has more executions of #{target.name} than Firefight reads, so the newest may be missing."
          result.merge("content" => result["content"] + [ { "type" => "text", "text" => note } ])
        end

        private

        def job_target(environment_row, asked)
          target = find(environment_row, asked)
          fail!("#{target.name} is a #{target.type}. This works on a Cloud Run job.") unless target.job?

          target
        end

        def execution_of(environment_row, target, asked)
          name = short(asked.to_s.strip)
          api(environment_row).job_execution(target.project, target.location, target.name, name)
        rescue GoogleCloudApi::NotFound
          fail!("#{target.name} has no execution called #{name}. list_executions shows them.")
        end

        # Every region's jobs, as run_items reads every region's services.
        def job_items(api, project)
          locations = api.run_locations(project)
          complete = locations.complete
          found = locations.items.filter_map { |location| location["locationId"] }.flat_map do |location|
            jobs = api.run_jobs(project, location)
            complete &&= jobs.complete
            jobs.items.map { |job| job_item(job) }
          end
          [ found, complete ]
        end

        # A job stands as its last execution ended, or as its own condition says while it never ran.
        def job_item(job)
          target = Target.parse(job["name"])
          latest = job["latestCreatedExecution"].to_h
          container = Array(job.dig("template", "template", "containers")).first.to_h
          { type: TYPE_JOB, id: job["name"], name: target&.name || job["name"], location: target&.location,
            status: COMPLETION_WORDS[latest["completionStatus"]] || run_status(job), hosts: [], source: job,
            details: { TYPE => TYPE_JOB, "region" => target&.location, "image" => container["image"], "latest_execution" => short(latest["name"]).presence,
                       ResourceMap::TAGS => job["labels"].presence }.compact }
        end

        # A job's settings and the Cloud SQL instances it mounts, read from its task template as a service's are.
        def job_links(key, job, reading)
          task = { "template" => job.dig("template", "template").to_h }
          reading.uses.concat(run_settings(key, task, reading.workspace))
          reading.links.concat(cloud_sql_links(key, task))
        end

        def job_lines(job)
          latest = job["latestCreatedExecution"].to_h
          execution = job["template"].to_h
          task = execution["template"].to_h
          container = Array(task["containers"]).first.to_h
          [
            "#{short(job['name'])}, a Cloud Run job, #{job_item(job)[:status]}",
            ("Last execution #{short(latest['name'])}, made #{latest['createTime']}, #{COMPLETION_WORDS.fetch(latest['completionStatus'], 'unknown')}" if latest["name"]),
            "#{job['executionCount'].to_i} executions so far",
            "Runs #{container['image']}",
            "#{execution['taskCount'] || 1} tasks an execution, #{execution['parallelism'] || 'any number'} at a time, " \
            "each retried up to #{task['maxRetries'] || 3} times within #{task['timeout'] || 'the default timeout'}",
            "Last changed #{job['updateTime']} by #{job['lastModifier'] || 'unknown'}",
            "list_executions shows its executions and each one's tasks."
          ]
        end

        # An execution as every run history reads it, from when it started (or was made, while it waits) to when it
        # completed.
        def execution_run(execution, target)
          status = execution_status(execution)
          History::Run.new(
            id: short(execution["name"]), name: target.name, status: status,
            started_at: Capabilities::RunHistory.time(execution["startTime"] || execution["createTime"]),
            finished_at: (Capabilities::RunHistory.time(execution["completionTime"]) if History::FINISHED.include?(status)),
            url: execution["logUri"].presence, detail: execution_detail(execution, status)
          )
        end

        # By its Completed condition, or while it has none, by its counts and times.
        def execution_status(execution)
          completed = Array(execution["conditions"]).find { |condition| condition["type"] == COMPLETED }
          if completed
            return History::CANCELLED if completed["executionReason"] == CANCELLED
            return History::RUNNING if completed["executionReason"] == CANCELLING

            return History.status(completed["state"], CONDITION_STATES)
          end
          if execution["completionTime"].present?
            return History::FAILED if execution["failedCount"].to_i.positive?
            return History::CANCELLED if execution["cancelledCount"].to_i.positive?

            return History::SUCCEEDED
          end
          execution["startTime"].present? ? History::RUNNING : History::QUEUED
        end

        def execution_detail(execution, status)
          total = execution["taskCount"].to_i
          counts = [
            ("#{execution['succeededCount'].to_i} of #{total} #{'task'.pluralize(total)} succeeded" if total.positive?),
            ("#{execution['failedCount']} failed" if execution["failedCount"].to_i.positive?),
            ("#{execution['runningCount']} running" if execution["runningCount"].to_i.positive?),
            ("#{execution['retriedCount']} retried" if execution["retriedCount"].to_i.positive?)
          ]
          message = Array(execution["conditions"]).find { |condition| condition["type"] == COMPLETED }&.dig("message") if status == History::FAILED
          [ *counts, message.presence ].compact.join(", ").presence
        end

        # Each task, in its index's order, with how its last attempt ended and how to read its own lines.
        def task_parts(target, execution, tasks)
          tasks.sort_by { |task| task["index"].to_i }.map do |task|
            status = task_status(task)
            started = Capabilities::RunHistory.time(task["startTime"])
            finished = Capabilities::RunHistory.time(task["completionTime"]) if History::FINISHED.include?(status)
            History::Part.new(
              id: task["index"].to_i.to_s, name: "task #{task['index'].to_i}", status: status, started_at: started, finished_at: finished,
              url: task["logUri"].presence, detail: task_detail(task),
              log: { History::LOG_TOOL => "search_logs",
                     History::LOG_ARGUMENTS => { "resource" => target.id, "run" => "#{short(execution['name'])}/#{task['index'].to_i}",
                                                 "start" => started&.utc&.iso8601, "end" => (finished || (Time.current if started))&.utc&.iso8601 }.compact }
            )
          end
        end

        def task_status(task)
          completed = Array(task["conditions"]).find { |condition| condition["type"] == COMPLETED }
          return History.status(completed["state"], CONDITION_STATES) if completed
          if task["completionTime"].blank?
            return task["startTime"].present? ? History::RUNNING : History::QUEUED
          end

          attempt = task["lastAttemptResult"].to_h
          attempt.dig("status", "code").to_i.zero? && attempt["exitCode"].to_i.zero? ? History::SUCCEEDED : History::FAILED
        end

        def task_detail(task)
          attempt = task["lastAttemptResult"].to_h
          [ attempt.dig("status", "message").presence, ("exit code #{attempt['exitCode']}" if attempt["exitCode"].to_i.nonzero?),
            ("retried #{task['retried']} #{'time'.pluralize(task['retried'].to_i)}" if task["retried"].to_i.positive?) ].compact.join(", ").presence
        end

        # A job's lines, or a Cloud Deploy pipeline's or stage's, which are what its rollouts' jobs printed.
        def run_logs(environment_row, target, arguments)
          target.job? ? job_logs(environment_row, target, arguments) : rollout_logs(environment_row, target, arguments)
        end

        # A job's own lines, all of them or one execution's or one task's, by the labels Cloud Logging writes on them.
        def job_logs(environment_row, target, arguments)
          stream = arguments["stream"].presence || STREAM_APP
          fail!("A Cloud Run job keeps only what it prints, so ask for stream #{STREAM_APP}.") unless stream == STREAM_APP

          run, step = arguments["run"].to_s.strip.delete_prefix("#{target.id}/executions/").split("/", 2).map(&:presence)
          fail!("run is an execution's name, and a task's index after it for one task, such as nightly-x2k9p/1.") if step && !step.match?(/\A\d+\z/)

          started, ended = run_window(arguments) { execution_of(environment_row, target, run) if run }
          scope = [ "resource.type=#{quote(JOB_LOG)}", "resource.labels.job_name=#{quote(target.name)}", "resource.labels.location=#{quote(target.location)}",
                    ("labels.#{quote(EXECUTION_LABEL)}=#{quote(run)}" if run), ("labels.#{quote(TASK_LABEL)}=#{quote(step)}" if step) ].compact
          read_lines(environment_row, target, scope, started, ended, arguments, [ run && "execution #{run}", step && "task #{step}" ].compact,
                     page_link(environment_row, target.project, TYPE_JOB))
        end

        # The range asked, or with none the run's own time, a minute either side, from what the block reads of it.
        def run_window(arguments)
          asked = arguments.slice("minutes", "start", "end").compact_blank
          return Capabilities::Answers.range(arguments) if asked.any?

          run = yield
          return Capabilities::Answers.range(arguments) unless run

          started = Capabilities::RunHistory.time(run["startTime"] || run["deployStartTime"] || run["createTime"]) || 1.hour.ago
          ended = Capabilities::RunHistory.time(run["completionTime"] || run["deployEndTime"])
          [ started - 1.minute, ended ? [ ended + 1.minute, Time.current ].min : Time.current ]
        end

        def read_lines(environment_row, target, scope, started, ended, arguments, narrowed, link)
          limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
          filter = [ *scope, "timestamp>=#{quote(started.utc.iso8601)}", "timestamp<=#{quote(ended.utc.iso8601)}", *text_filters(arguments) ].join(" AND ")
          entries = api(environment_row).log_entries(target.project, filter, limit: limit)
          lines = entries.map { |entry| log_line(entry, ended) }
          asked = "#{target.name}#{" (#{narrowed.join(', ')})" if narrowed.any?} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
          Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: link)
        end
      end
    end
  end
end
