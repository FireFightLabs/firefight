module Integrations
  module Packs
    class Railway < NativePack
      # A cron job's runs, each an execution of one of its deployments, read as the CLI's railway cron list reads them
      # (railwayapp/cli, src/gql/queries/strings/DeploymentInstanceExecutions.graphql, and docs content/docs/cli/cron.md).
      # Railway documents no page of one run, so each links to the service.
      module CronRuns
        CRON_RUNS = "cron_runs".freeze
        CRON_RUN = "cron run".freeze
        RUN_LIMIT = 20
        # The CLI reads at most this many runs (docs, railway cron list --limit), and a run named by its id is found among them.
        MOST_RUNS = 1000
        # A run's statuses (docs, Run statuses, and schema enum DeploymentInstanceStatus) in Firefight's words. A run skipped
        # because the one before it still ran, and one stopped or whose deployment was removed, did not finish its work.
        RUN_STATUSES = {
          "created" => Capabilities::History::QUEUED, "initializing" => Capabilities::History::QUEUED,
          "restarting" => Capabilities::History::RUNNING, "running" => Capabilities::History::RUNNING,
          "exited" => Capabilities::History::SUCCEEDED, "crashed" => Capabilities::History::FAILED,
          "skipped" => Capabilities::History::CANCELLED, "stopped" => Capabilities::History::CANCELLED,
          "removed" => Capabilities::History::CANCELLED, "removing" => Capabilities::History::CANCELLED
        }.freeze
        SKIPPED = "SKIPPED".freeze
        # A run's log is read to a little past when it completed, as the CLI rounds its end up.
        LOG_MARGIN = 1.minute

        def self.included(pack)
          pack.tool CRON_RUNS,
                    summary: "Lists a cron job's recent runs with how each ended.",
                    description: "A Railway cron job's recent runs, newest first, each with its status (exited, crashed, skipped because " \
                                 "the run before still ran, and the rest), when it started and finished, how long it took and the " \
                                 "deployment it ran, and how long finished runs usually take. Name a run to read it with how to read its log",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "environment" => ENVIRONMENT_PARAM,
                        "name" => { "type" => "string", "description" => "Only runs of this kind, cron run (optional)" },
                        "run" => { "type" => "string", "description" => "Only this run, by its id, with how to read its log (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many runs (optional, #{RUN_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true
        end

        def cron_runs(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          unless resource[:type] == CRON_JOB
            fail! "#{resource[:name]} has no cron schedule in this environment, so it has no cron runs. deploy_history lists its deployments."
          end

          page = link(environment_row, resource)
          asked = arguments["run"].to_s.strip.presence
          limit = asked ? MOST_RUNS : [ Capabilities::Answers.limit(arguments, RUN_LIMIT), MOST_RUNS ].min
          runs = api(environment_row).cron_runs(environment(environment_row)["id"], resource[:id], limit: limit).map { |run| cron_run(run, page) }
          return Capabilities::History.result(runs, what: resource[:name], link: page, name: arguments["name"], limit: limit) unless asked

          found = runs.find { |run| run.named?(asked) } || fail!("#{resource[:name]} has no run #{asked} among its latest #{MOST_RUNS}. cron_runs lists its recent runs.")
          Capabilities::History.result([ found.with(parts: [ run_part(resource, found) ]) ], what: resource[:name], link: page)
        end

        private

        def cron_run(run, page)
          status = Capabilities::History.status(run["status"], RUN_STATUSES)
          finished = Telemetry.parse_time(run["completedAt"])
          finished ||= Telemetry.parse_time(run["updatedAt"]) if Capabilities::History::FINISHED.include?(status)
          skipped = ", skipped because the run before it still ran" if run["status"] == SKIPPED
          Capabilities::History::Run.new(id: run["id"], name: CRON_RUN, status: status, started_at: Telemetry.parse_time(run["createdAt"]),
                                         finished_at: finished, url: page.url, detail: "deployment #{run['deploymentId']}#{skipped}")
        end

        # The run itself, with its app log over the time it ran, which is how the CLI points at one run's lines.
        def run_part(resource, run)
          window = { "start" => run.started_at&.utc&.iso8601, "end" => (run.finished_at && (run.finished_at + LOG_MARGIN).utc.iso8601) }
          Capabilities::History::Part.new(
            id: run.id, name: CRON_RUN, status: run.status, started_at: run.started_at, finished_at: run.finished_at, url: run.url, detail: run.detail,
            log: { Capabilities::History::LOG_TOOL => "search_logs",
                   Capabilities::History::LOG_ARGUMENTS => { "resource" => resource[:id], "type" => APP, ENVIRONMENT => @asked_environment, **window }.compact }
          )
        end
      end
    end
  end
end
