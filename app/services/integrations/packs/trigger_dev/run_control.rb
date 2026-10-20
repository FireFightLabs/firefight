module Integrations
  module Packs
    class TriggerDev
      # Stopping and starting runs again, one at a time or many at once (cancel_run_v1, replay_run_v1,
      # create_bulk_action_v1), and the environment's deployments as run history, each timed from when it was made to when
      # it deployed (list_deployments_v1, get_deployment_v1), as Trigger.dev's OpenAPI spec gives them
      # (triggerdotdev/trigger.dev, docs/v3-openapi.yaml).
      module RunControl
        RUN = { "type" => "string", "description" => "The run's id, starting run_, as list_runs shows it" }.freeze
        # A bulk action selects at most this many runs by id (CreateBulkActionRequestBody).
        BULK_IDS = 500
        CANCEL = "cancel".freeze
        REPLAY = "replay".freeze
        BULK_PENDING = "PENDING".freeze
        # A deployment in run history, and what Trigger.dev calls one still installing its dependencies (get_deployment_v1).
        DEPLOY_RUN = "deploy".freeze
        # How many deployments one deployment's times are looked for among, since reading it by its id gives none.
        DEPLOYMENT_LOOKUP = 100
        BULK_SELECTION = {
          "runs" => { "type" => "array", "items" => { "type" => "string" }, "description" => "These runs, by their ids, at most #{BULK_IDS} (this or a filter)" },
          "task" => { "type" => "string", "description" => "Only runs of this task, by its identifier (a filter)" },
          "status" => { "type" => "array", "items" => { "type" => "string", "enum" => RUN_STATUSES }, "description" => "Only runs in these states (a filter)" },
          "version" => { "type" => "string", "description" => "Only runs on this version, such as 20250228.1 (a filter)" },
          "minutes" => { "type" => "integer", "description" => "Only runs created this many minutes back from now (with a filter, optional)" },
          "start" => { "type" => "string", "description" => "Only runs created from this ISO 8601 time (with a filter, optional)" },
          "end" => { "type" => "string", "description" => "Only runs created until this ISO 8601 time (with a filter, optional)" }
        }.freeze

        def self.included(pack)
          pack.tool :cancel_run,
                    summary: "Cancels a Trigger.dev run that has not finished.",
                    description: "Stop one run that is still waiting or executing, by its id. Its retries stop too. A run that already " \
                                 "ended is refused",
                    params_schema: { "type" => "object", "properties" => { "run" => RUN }, "required" => [ "run" ] },
                    read_only: false

          pack.tool :replay_run,
                    summary: "Starts a Trigger.dev run again with the same payload and options.",
                    description: "Start a new run of the same task with the same payload, metadata and options as one run, by its id, " \
                                 "such as one that failed for a reason since fixed. It runs on the current version. The run it copies " \
                                 "stays as it was",
                    params_schema: { "type" => "object", "properties" => { "run" => RUN }, "required" => [ "run" ] },
                    read_only: false

          pack.tool :bulk_cancel_runs,
                    summary: "Cancels many Trigger.dev runs at once, by id or by a filter.",
                    description: "Cancel many runs that have not finished at once, by their ids or by a filter of task, status, version " \
                                 "and when they were created, such as every queued run of a task that floods. Trigger.dev works through " \
                                 "them after the answer, and api_read on the bulk action's id says how far it got",
                    params_schema: { "type" => "object", "properties" => BULK_SELECTION },
                    read_only: false

          pack.tool :bulk_replay_runs,
                    summary: "Starts many Trigger.dev runs again at once, by id or by a filter.",
                    description: "Start many runs again at once, each with its own payload and options, by their ids or by a filter of " \
                                 "task, status, version and when they were created, such as every run of a task that failed in an outage. " \
                                 "Trigger.dev works through them after the answer, and api_read on the bulk action's id says how far it got",
                    params_schema: { "type" => "object", "properties" => BULK_SELECTION },
                    read_only: false

          pack.tool :abort_bulk_action,
                    summary: "Stops a Trigger.dev bulk cancel or replay that is still working through runs.",
                    description: "Stop a bulk action that is still pending, by the id bulk_cancel_runs or bulk_replay_runs answered, so it " \
                                 "takes no more runs. Runs it already cancelled or replayed stay as they are. One that ended is refused",
                    params_schema: { "type" => "object",
                                     "properties" => { "bulk_action" => { "type" => "string", "description" => "The bulk action, by its id starting bulk_" } },
                                     "required" => [ "bulk_action" ] },
                    read_only: false

          pack.tool :deploy_history,
                    summary: "Lists the environment's deployments with how long each took to deploy.",
                    description: "The environment's deployments as runs, newest first, each with its version, status, when it was made " \
                                 "and deployed, how long it took and how long finished ones usually take, or one deployment by its id",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "name" => { "type" => "string", "description" => "Only runs of this kind, deploy (optional)" },
                        "run" => { "type" => "string", "description" => "Only this deployment, by its id as list_deployments shows it (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many deployments (optional, #{DEPLOYMENT_LIMIT})" }
                      }
                    },
                    read_only: true
        end

        def cancel_run(environment_row:, arguments:)
          id = run_id_of(arguments)
          api = api(environment_row)
          run = api.run(id)
          status = Capabilities::History.status(run["status"], HISTORY_STATUSES)
          fail!("Run #{id} of #{run['taskIdentifier']} already ended, #{run['status']}, so there is nothing to cancel.") if Capabilities::History::FINISHED.include?(status)

          changing("cancel run #{id}") { api.cancel_run(id) }
          Telemetry.result("Run #{id} of #{run['taskIdentifier']} is cancelled, with any retries it had left. #{FOLLOW_RUN}", link: run_link(environment_row, id))
        end

        def replay_run(environment_row:, arguments:)
          id = run_id_of(arguments)
          made = changing("replay run #{id}") { api(environment_row).replay_run(id) }
          new_id = made["id"].presence
          Telemetry.result("Run #{id} runs again as #{new_id || 'a new run'}, with the same payload and options, on the current version. " \
                           "#{FOLLOW_RUN}", link: run_link(environment_row, new_id || id))
        end

        def bulk_cancel_runs(environment_row:, arguments:) = bulk(environment_row, arguments, CANCEL)

        def bulk_replay_runs(environment_row:, arguments:) = bulk(environment_row, arguments, REPLAY)

        # Only a bulk action still pending takes more runs (BulkActionObject status), so one that ended is refused.
        def abort_bulk_action(environment_row:, arguments:)
          id = arguments["bulk_action"].to_s.strip
          fail!("Say which bulk action, by its id starting bulk_.") unless id.start_with?("bulk_")

          api = api(environment_row)
          action = begin
            api.bulk_action_status(id)
          rescue TriggerDevApi::Error => error
            raise if error.is_a?(Integrations::RateLimited)

            fail!("Trigger.dev could not read bulk action #{id}: #{error.message}")
          end
          fail!("Bulk action #{id} already ended, #{action['status']}, so there is nothing to stop.") unless action["status"] == BULK_PENDING

          changing("abort bulk action #{id}") do
            api.abort_bulk_action(id)
          rescue TriggerDevApi::Error => error
            raise if error.is_a?(Integrations::RateLimited) || refused_for_key?(error)

            # One that finished between the read and the abort is said as ended. Otherwise the abort's own error stands.
            now = begin
              api.bulk_action_status(id)["status"]
            rescue TriggerDevApi::Error
              raise error
            end
            raise error if now == BULK_PENDING

            fail!("Bulk action #{id} ended while it was being stopped, #{now}, so there is nothing to stop.")
          end
          counts = action["counts"].to_h
          Telemetry.result("Bulk action #{id} (#{action['type'].to_s.downcase}) is stopped and takes no more runs. It had done #{counts['success'].to_i + counts['failure'].to_i} " \
                           "of #{counts['total'] || 'its'} runs, and those stay as they are. #{no_page}", link: nil)
        end

        # Times come from the list, since reading one deployment by its id says no times. One past the newest
        # DEPLOYMENT_LOOKUP keeps its status and version without them.
        def deploy_history(environment_row:, arguments:)
          api = api(environment_row)
          asked = arguments["run"].to_s.strip.presence
          return one_deploy(api, asked) if asked

          deployments = api.deployments(limit: Capabilities::Answers.limit(arguments, DEPLOYMENT_LIMIT))
          Capabilities::History.result(deployments.map { |deployment| deploy_run(deployment) }, what: "this environment's deployments",
                                       name: arguments["name"], link: nil)
        end

        private

        FOLLOW_RUN = "list_runs with the run's id says how it goes.".freeze

        def run_id_of(arguments)
          id = arguments["run"].to_s.strip.delete_prefix("#")
          fail!("Say which run, by its id starting run_. list_runs shows them.") unless id.start_with?("run_")

          id
        end

        # A key whose preset cannot write runs is said with what to give it.
        def changing(what)
          yield
        rescue TriggerDevApi::Error => error
          raise if error.is_a?(Integrations::RateLimited) || !refused_for_key?(error)

          fail!(Sentence.join("Trigger.dev refused to #{what}", error,
                              after: "This environment's API key cannot make that change. In Trigger.dev, create a key whose preset can " \
                                     "write runs, such as No restrictions, and reconnect with it"))
        end

        def refused_for_key?(error) = error.message.start_with?("Trigger.dev answered 401", "Trigger.dev answered 403")

        # Never every run in the environment: a bulk action names its runs or filters by task, status or version.
        def bulk(environment_row, arguments, action)
          ids = Array(arguments["runs"]).map { |id| id.to_s.strip }.compact_blank.uniq
          fail!("runs holds at most #{BULK_IDS} ids. Filter by task and status instead.") if ids.size > BULK_IDS
          filter = bulk_filter(arguments)
          fail_policy!("Name the runs, or filter by task, status or version, since Firefight never #{action}s every run at once.") if ids.empty? && filter.nil?

          name = "Firefight: #{action} #{ids.any? ? "#{ids.size} runs" : filter.except('from', 'to').to_json}".truncate(255)
          made = changing("#{action} runs") { api(environment_row).bulk_action(action, name: name, run_ids: ids.presence, filter: (filter if ids.empty?)) }
          what = ids.any? ? "#{ids.size} runs" : "the runs matching #{filter.to_json}"
          Telemetry.result("Trigger.dev #{action == CANCEL ? 'cancels' : 'replays'} #{what} as bulk action #{made['id'] || 'unknown'}, working through " \
                           "them now. api_read on /api/v1/bulk-actions/#{made['id']} says how many it has done, and abort_bulk_action stops it. #{no_page}", link: nil)
        end

        # The spec's filter for a bulk action, with its times top level (BulkActionFilter), or nil when nothing narrows it.
        def bulk_filter(arguments)
          narrowed = {
            "taskIdentifier" => arguments["task"].to_s.strip.presence, "status" => (Array(arguments["status"]) & RUN_STATUSES).presence,
            "version" => arguments["version"].to_s.strip.presence
          }.compact
          return if narrowed.empty?

          return narrowed if arguments.values_at("minutes", "start", "end").all?(&:blank?)

          started, ended = Capabilities::Answers.range(arguments)
          narrowed.merge("from" => started.utc.iso8601, "to" => ended.utc.iso8601)
        end

        def deploy_run(deployment, detail: nil)
          status = Capabilities::History.status(deployment["status"], DEPLOYMENT_HISTORY_STATUSES)
          error = deployment["error"].presence || deployment["errorData"].presence
          said = [ ("short code #{deployment['shortCode']}" if deployment["shortCode"].present?), detail,
                   ("error #{Chat::SecretFree.redacted(error.is_a?(Hash) ? (error['message'] || error.to_json) : error.to_s).truncate(300)}" if error) ].compact
          Capabilities::History::Run.new(
            id: deployment["id"], name: DEPLOY_RUN, title: deployment["version"], status: status,
            started_at: Capabilities::RunHistory.time(deployment["createdAt"]),
            finished_at: (Capabilities::RunHistory.time(deployment["deployedAt"]) if status == Capabilities::History::SUCCEEDED),
            detail: [ ("version #{deployment['version']}" if deployment["version"].present?), *said ].join(", ").presence
          )
        end

        def one_deploy(api, id)
          deployment = begin
            api.deployment(id)
          rescue TriggerDevApi::Error => error
            raise if error.is_a?(Integrations::RateLimited)

            fail!("Trigger.dev could not read deployment #{id}: #{error.message}")
          end
          listed = api.deployments(limit: DEPLOYMENT_LOOKUP).find { |each| each["id"] == deployment["id"] }
          missing = listed ? nil : "made before the newest #{DEPLOYMENT_LOOKUP}, so its times are not known"
          run = deploy_run((listed || {}).merge(deployment.compact), detail: missing)
          Capabilities::History.result([ run.with(parts: []) ], what: "deployment #{deployment['version'] || id}", link: nil)
        end
      end
    end
  end
end
