module Integrations
  module Packs
    class Digitalocean
      # What happens to an App Platform app between deployments, and the changes that steer one: its events (deployments
      # and autoscaling, apps_list_events), its jobs' runs (apps_list_job_invocations and apps_get_job_invocation),
      # cancelling a deployment or a job run (apps_cancel_deployment, apps_cancel_job_invocation), deploying the newest
      # code (apps_create_deployment), and keeping or undoing a rollback (apps_commit_rollback, apps_revert_rollback), as
      # DigitalOcean's OpenAPI specification gives them (digitalocean/openapi, specification/resources/apps).
      module AppOperations
        EVENT_LIMIT = 20
        # The kinds of event apps_list_events filters by.
        EVENT_TYPES = %w[DEPLOYMENT AUTOSCALING].freeze
        DEPLOYMENT_ARGUMENT = { "type" => "string", "description" => "The deployment, by its id, as list_deployments or deploy_history shows it" }.freeze

        def self.included(pack)
          pack.tool :app_events,
                    summary: "Lists an app's deployments and autoscaling, newest first.",
                    description: "An App Platform app's events, newest first: each deployment with its phase and cause, and each time " \
                                 "autoscaling changed how many instances a component runs, from how many to how many and the metric that " \
                                 "moved it. Use it to see when an app scaled itself around a problem",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => APP,
                        "type" => { "type" => "string", "enum" => EVENT_TYPES, "description" => "Only events of this kind (optional, both)" },
                        "limit" => { "type" => "integer", "description" => "At most this many events (optional, #{EVENT_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true

          pack.tool :cancel_deployment,
                    summary: "Cancels an App Platform deployment that is still building or deploying.",
                    description: "Stop an App Platform deployment that is still building or deploying, by its id. The deployment live " \
                                 "before it keeps serving. One that already ended is refused",
                    params_schema: { "type" => "object", "properties" => { "resource" => APP, "deployment" => DEPLOYMENT_ARGUMENT },
                                     "required" => %w[resource deployment] },
                    read_only: false

          pack.tool :cancel_job_run,
                    summary: "Cancels a run of an App Platform job that has not finished.",
                    description: "Stop one run of an App Platform job, by the id deploy_history shows, such as a migration or a scheduled " \
                                 "job that hangs. A run that already ended is refused",
                    params_schema: { "type" => "object",
                                     "properties" => { "resource" => APP, "run" => { "type" => "string", "description" => "The job run, by its id" } },
                                     "required" => %w[resource run] },
                    read_only: false

          pack.tool :redeploy_app,
                    summary: "Deploys an App Platform app again from the newest commit of its branches.",
                    description: "Make a new deployment of an App Platform app from the newest commit of each component's branch, as a " \
                                 "push would. force_build builds every component again from source rather than reusing a cached build, for " \
                                 "a build that went bad. It refuses an app pinned by a rollback",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => APP,
                        "force_build" => { "type" => "boolean", "description" => "Build again from source even where a cached build fits (optional, false)" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: false

          pack.tool :commit_rollback,
                    summary: "Keeps an App Platform app's rollback for good and lets it deploy again.",
                    description: "Keep the rollback an App Platform app is pinned to for good, so it deploys again, on a push too. The " \
                                 "newer deployment the rollback replaced cannot be put back after this",
                    params_schema: { "type" => "object", "properties" => { "resource" => APP }, "required" => [ "resource" ] },
                    read_only: false

          pack.tool :revert_rollback,
                    summary: "Undoes an App Platform app's rollback and lets it deploy again.",
                    description: "Undo the rollback an App Platform app is pinned to: DigitalOcean deploys the app as it was before the " \
                                 "rollback, as a new deployment, and lets it deploy again, on a push too",
                    params_schema: { "type" => "object", "properties" => { "resource" => APP }, "required" => [ "resource" ] },
                    read_only: false
        end

        def app_events(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          type = arguments["type"].to_s.strip.upcase.presence
          fail!("type must be one of #{EVENT_TYPES.join(', ')}.") if type && EVENT_TYPES.exclude?(type)

          events = api(environment_row).events(resource[:id], limit: Capabilities::Answers.limit(arguments, EVENT_LIMIT), type: type)
          link = link_of(environment_row, resource)
          return Telemetry.result("#{resource[:name]} has no #{type ? "#{type.downcase} " : ''}events.", link: link) if events.empty?

          Telemetry.result("Latest #{events.size} events of #{resource[:name]}, newest first.\n#{events.map { |event| event_line(event) }.join("\n")}", link: link)
        end

        def cancel_deployment(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          id = arguments["deployment"].to_s.strip
          fail!("Say which deployment to cancel, by the id list_deployments shows.") if id.empty?

          api = api(environment_row)
          deployment = known(resource, "deployment #{id}") { api.deployment(resource[:id], id) }
          if Capabilities::History::FINISHED.include?(Capabilities::History.status(deployment["phase"], DEPLOYMENT_PHASES))
            fail!("Deployment #{id} of #{resource[:name]} already ended, #{deployment['phase']}, so there is nothing to cancel.")
          end

          cancelled = change { api.cancel_deployment(resource[:id], id) }
          Telemetry.result("Deployment #{id} of #{resource[:name]} is cancelled, now #{cancelled['phase'] || 'CANCELED'}. The deployment live " \
                           "before it keeps serving.", link: deployment_link(environment_row, resource[:id], id))
        end

        def cancel_job_run(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          id = arguments["run"].to_s.strip
          fail!("Say which job run to cancel, by the id deploy_history shows.") if id.empty?

          api = api(environment_row)
          invocation = known(resource, "job run #{id}") { api.job_invocation(resource[:id], id) }
          job = invocation["job_name"].to_s
          if Capabilities::History::FINISHED.include?(Capabilities::History.status(invocation["phase"], JOB_PHASES))
            fail!("Run #{id} of job #{job} already ended, #{invocation['phase']}, so there is nothing to cancel.")
          end

          cancelled = change { api.cancel_job_invocation(resource[:id], id, job_name: job) }
          Telemetry.result("Run #{id} of job #{job} in #{resource[:name]} is cancelled, now #{cancelled['phase'] || 'CANCELED'}.", link: link_of(environment_row, resource))
        end

        def redeploy_app(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          api = api(environment_row)
          refuse_pinned!(resource, api.app(resource[:id]))
          force = ActiveModel::Type::Boolean.new.cast(arguments["force_build"]) == true
          made = change { api.create_deployment(resource[:id], force_build: force) }
          id = made.dig("deployment", "id")
          Telemetry.result("#{resource[:name]} is deploying the newest commit of each component's branch#{', built again from source' if force}, as " \
                           "deployment #{id || 'unknown'}.", link: id ? deployment_link(environment_row, resource[:id], id) : link_of(environment_row, resource))
        end

        def commit_rollback(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          api = api(environment_row)
          pinned = pinned_deployment!(resource, api.app(resource[:id]))
          change { api.commit_rollback(resource[:id]) }
          Telemetry.result("#{resource[:name]} keeps deployment #{pinned} for good and deploys again, on a push too.", link: link_of(environment_row, resource))
        end

        def revert_rollback(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"], only: KIND_APP)
          api = api(environment_row)
          pinned = pinned_deployment!(resource, api.app(resource[:id]))
          made = change { api.revert_rollback(resource[:id]) }
          Telemetry.result("#{resource[:name]} no longer stays on deployment #{pinned}. It deploys as it was before the rollback, as deployment " \
                           "#{made.dig('deployment', 'id') || 'unknown'}, and deploys again on a push.", link: link_of(environment_row, resource))
        end

        private

        def pinned_deployment!(resource, app)
          app.dig("pinned_deployment", "id").presence ||
            fail!("#{resource[:name]} is not pinned by a rollback, so there is no rollback to keep or undo.")
        end

        def refuse_pinned!(resource, app)
          pinned = app.dig("pinned_deployment", "id").presence
          return unless pinned

          fail!("#{resource[:name]} is pinned to deployment #{pinned} by a rollback, so DigitalOcean deploys nothing new until the rollback is " \
                "kept with commit_rollback or undone with revert_rollback.")
        end

        def event_line(event)
          what = if event["type"] == "AUTOSCALING"
            scaled = event.dig("autoscaling", "components").to_h.map do |name, change|
              "#{name} #{change['from']} to #{change['to']}#{" on #{change['triggering_metric']}" if change['triggering_metric'].present?}"
            end
            [ "autoscaling #{event.dig('autoscaling', 'phase')}".squish, *scaled ].join(", ")
          else
            deployment = event["deployment"].to_h
            [ "deployment #{event['deployment_id']}", deployment["phase"], deployment["cause"].presence ].compact.join(", ")
          end
          "- #{event['created_at']}: #{what}"
        end

        # A job's run in the words every run history uses, from when it started, or was made when it has not.
        def job_run(environment_row, resource, invocation)
          status = Capabilities::History.status(invocation["phase"], JOB_PHASES)
          trigger = invocation["trigger"].to_h
          started_by = case trigger["type"]
          when "SCHEDULE" then "on schedule #{trigger.dig('scheduled', 'schedule', 'cron')}".strip
          when "MANUAL" then "by hand#{" by #{trigger.dig('manual', 'user', 'full_name')}" if trigger.dig('manual', 'user', 'full_name').present?}"
          end
          Capabilities::History::Run.new(
            id: invocation["id"], name: "#{JOB_RUN} #{invocation['job_name']}", status: status,
            started_at: Telemetry.parse_time(invocation["started_at"] || invocation["created_at"]),
            finished_at: (Telemetry.parse_time(invocation["completed_at"]) if Capabilities::History::FINISHED.include?(status)),
            url: link_of(environment_row, resource).url, detail: [ started_by, ("deployment #{invocation['deployment_id']}" if invocation["deployment_id"].present?) ].compact.join(", ").presence
          )
        end

        # One job run by its id, with its log as its one part.
        def one_job_run(environment_row, resource, id)
          invocation = known(resource, "deployment or job run #{id}") { api(environment_row).job_invocation(resource[:id], id) }
          run = job_run(environment_row, resource, invocation)
          log = { "resource" => resource[:id], "job_invocation" => invocation["id"] || id, "component" => invocation["job_name"].presence }.compact
          part = Capabilities::History::Part.new(id: invocation["id"] || id, name: run.name, status: run.status, started_at: run.started_at,
                                                 finished_at: run.finished_at, url: run.url,
                                                 log: { Capabilities::History::LOG_TOOL => "app_logs", Capabilities::History::LOG_ARGUMENTS => log })
          Capabilities::History.result([ run.with(parts: [ part ]) ], what: resource[:name], link: link_of(environment_row, resource))
        end
      end
    end
  end
end
