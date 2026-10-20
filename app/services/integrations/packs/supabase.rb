module Integrations
  module Packs
    # What Supabase's MCP server has no tool for, read and changed through Supabase's Management API with the connection's
    # credentials, beside the server's tools on the same connection: a branch's action runs and their logs, how each of a
    # project's services stands, its metrics, its backups, and restarting it or restoring its database to a moment. Paths,
    # parameters and fields are the ones the Management API's OpenAPI description gives (api.supabase.com/api/v1-json).
    # The server takes a personal access token or a sign-in as Bearer, and the Management API takes the same. A connection
    # made read only is offered none of the changes, as the server leaves out its own, and one scoped to a project reaches
    # only that project.
    class Supabase < NativePack
      PROVIDER = MapReaders::Supabase::NAME
      PROVIDER_KEY = MapReaders::Supabase::PROVIDER
      SCOPED_TO = "project_ref".freeze
      READ_ONLY = "read_only".freeze
      RUN_LIMIT = 20
      RUN_MOST = 100
      LOG_LINES = 200
      LOG_MOST = 1_000
      # Two readings this far apart give how busy the CPUs were, since Supabase counts CPU time as a counter.
      CPU_SAMPLE_SECONDS = 5
      READINGS = %w[cpu memory disk].freeze
      # The service the database's host readings are labelled with (supabase/supabase-grafana, docs/metrics.md).
      DB_SERVICE = "db".freeze
      BRANCHES_PAGE = "branches".freeze
      RUN_LOGS = "get_action_run_logs".freeze
      # The pages Supabase's own guides link to (guides/platform/backups, guides/deployment/branching, where a run's details_url is
      # its branch's branches page).
      BACKUPS_PAGE = "database/backups/pitr".freeze

      PROJECT = { "type" => "string", "description" => "The project, or a preview branch's own project, by its ref. A connection scoped to one project may leave it out" }.freeze
      RUN = { "type" => "string", "description" => "An action run's id, as list_action_runs gives it" }.freeze

      tool :list_action_runs,
           summary: "Lists a branch's action runs, which clone, migrate, seed and deploy it.",
           description: "A branch's action runs, newest first: each run Supabase made to clone, pull, migrate, seed and deploy it, with " \
                        "how it stands, when it started and finished and how long finished ones usually take. Give the branch's own " \
                        "project ref, as list_branches gives it, or the project's for its default branch. Supabase says how only the " \
                        "branch's newest run ended, and an older one whose every step exited counts as finished well",
           params_schema: { "type" => "object", "properties" => { "project_id" => PROJECT, "limit" => { "type" => "integer", "description" => "At most this many (optional, #{RUN_LIMIT})" } } },
           read_only: true

      tool :get_action_run,
           summary: "Shows one action run of a branch with how each of its steps went.",
           description: "One action run of a branch with its steps, clone, pull, health, configure, migrate, seed and deploy, each " \
                        "with its state and when it last changed. get_action_run_logs reads what it printed",
           params_schema: { "type" => "object", "properties" => { "project_id" => PROJECT, "run_id" => RUN }, "required" => [ "run_id" ] },
           read_only: true

      tool RUN_LOGS,
           summary: "Shows what one action run of a branch printed.",
           description: "What one action run of a branch printed, the last lines first cut to the newest, with only the lines " \
                        "containing text when it is given. Use it to see why a migration or seed failed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "project_id" => PROJECT, "run_id" => RUN,
               "text" => { "type" => "string", "description" => "Only lines containing this (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many of the last lines (optional, #{LOG_LINES})" }
             },
             "required" => [ "run_id" ]
           },
           read_only: true

      tool :get_project_health,
           summary: "Shows how a project and each of its services stand now.",
           description: "How a project stands now: its status, region and Postgres version, and each of its services (the database, " \
                        "its pooler, auth, the REST API, realtime and storage) as healthy, coming up or unhealthy, with the error " \
                        "Supabase gave for one that is not",
           params_schema: { "type" => "object", "properties" => { "project_id" => PROJECT } },
           read_only: true

      tool :get_project_metrics,
           summary: "Shows a project's CPU, memory and disk use now, and any other metric it reports.",
           description: "A project's database host as it is now: how busy its CPUs are (read twice #{CPU_SAMPLE_SECONDS} seconds apart), " \
                        "how much memory and how much of each disk is used, from the metrics Supabase reports in the Prometheus format. " \
                        "names reads any other of its metrics, about 200, by their Prometheus names, such as node_load1. Supabase " \
                        "keeps no history of these, so each is one reading",
           params_schema: {
             "type" => "object",
             "properties" => {
               "project_id" => PROJECT,
               "readings" => { "type" => "array", "items" => { "type" => "string", "enum" => READINGS }, "description" => "Which of cpu, memory and disk (optional, all)" },
               "names" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Other metrics by their Prometheus name (optional)" }
             }
           },
           read_only: true

      tool :list_backups,
           summary: "Lists a project's backups and how far back it can be restored.",
           description: "A project's backups, newest first, each with its state and when it was taken, whether point in time " \
                        "recovery is on, and the earliest and latest moments it can restore to. restore_to_point_in_time takes one",
           params_schema: { "type" => "object", "properties" => { "project_id" => PROJECT } },
           read_only: true

      tool :restart_project,
           summary: "Restarts a project's database and services.",
           description: "Restart a project, which restarts its database and services. It is unreachable for a short while, and " \
                        "open connections are dropped. get_project_health says when it is back",
           params_schema: { "type" => "object", "properties" => { "project_id" => PROJECT } },
           read_only: false

      tool :restore_to_point_in_time,
           summary: "Restores a project's database to how it was at a moment.",
           description: "Restore a project's database to how it was at a moment, with point in time recovery, which must be on. " \
                        "Every change after that moment is lost, and the project is unavailable while it restores. list_backups " \
                        "says the earliest and latest moments it can restore to",
           params_schema: {
             "type" => "object",
             "properties" => { "project_id" => PROJECT, "to" => { "type" => "string", "description" => "The moment to restore to, as an ISO 8601 time" } },
             "required" => [ "to" ]
           },
           read_only: false

      def self.beside_server? = true

      # A connection made read only is offered none of the changes, as the server leaves out its own.
      def self.offers?(settings, definition) = definition.read_only || settings.field(READ_ONLY).to_s != "true"

      # A run's step as Supabase reports it, its container's state (ActionRunResponse, run_steps.status).
      STEP_STATES = {
        "created" => Capabilities::History::QUEUED, "running" => Capabilities::History::RUNNING, "restarting" => Capabilities::History::RUNNING,
        "paused" => Capabilities::History::RUNNING, "removing" => Capabilities::History::RUNNING, "exited" => Capabilities::History::SUCCEEDED,
        "dead" => Capabilities::History::FAILED
      }.freeze
      # How a branch's newest run ended, from the branch's status (BranchResponse.status).
      BRANCH_STATES = {
        "creating_project" => Capabilities::History::RUNNING, "running_migrations" => Capabilities::History::RUNNING,
        "migrations_passed" => Capabilities::History::SUCCEEDED, "functions_deployed" => Capabilities::History::SUCCEEDED,
        "migrations_failed" => Capabilities::History::FAILED, "functions_failed" => Capabilities::History::FAILED
      }.freeze
      ACTION_RUN = "action run".freeze
      HEALTHY = "ACTIVE_HEALTHY".freeze

      def list_action_runs(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        client = api(environment_row)
        runs = client.action_runs(ref, limit: Capabilities::Answers.limit(arguments, RUN_MOST, default: RUN_LIMIT))
        latest = latest_of(environment_row, client, ref)
        link = page_link(environment_row, ref, BRANCHES_PAGE)
        site = ConnectionSettings.of(environment_row).site
        Capabilities::History.result(runs.map { |run| run_of(run, ref, latest, site) }, what: "the action runs of #{ref}", link: link,
                                     limit: Capabilities::Answers.limit(arguments, RUN_MOST, default: RUN_LIMIT))
      end

      def get_action_run(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        client = api(environment_row)
        run = client.action_run(ref, required!(arguments, "run_id"))
        found = run_of(run, ref, latest_of(environment_row, client, ref), ConnectionSettings.of(environment_row).site, parts: true)
        Capabilities::History.result([ found ], what: "action run #{found.id} of #{ref}", link: page_link(environment_row, ref, BRANCHES_PAGE))
      rescue SupabaseApi::NotFound
        fail!("#{ref} has no action run #{arguments['run_id']}.")
      end

      def get_action_run_logs(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        run_id = required!(arguments, "run_id")
        lines = api(environment_row).action_run_logs(ref, run_id).to_s.lines.map(&:rstrip).compact_blank
        lines = lines.select { |line| line.include?(arguments["text"].to_s) } if arguments["text"].present?
        limit = Capabilities::Answers.limit(arguments, LOG_MOST, default: LOG_LINES)
        shown = lines.last(limit)
        text = if shown.empty?
          "Action run #{run_id} of #{ref} printed nothing#{' that matches' if arguments['text'].present?}."
        else
          cut = lines.size > shown.size ? " Only its last #{shown.size} of #{lines.size} lines are shown." : ""
          "What action run #{run_id} of #{ref} printed.#{cut}\n#{shown.join("\n")}"
        end
        Telemetry.result(text, link: page_link(environment_row, ref, BRANCHES_PAGE))
      rescue SupabaseApi::NotFound
        fail!("#{ref} has no action run #{run_id}.")
      end

      def get_project_health(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        client = api(environment_row)
        project = client.project(ref)
        services = client.health(ref)
        facts = [ ("status #{project['status']}" if project["status"]), ("region #{project['region']}" if project["region"]),
                  ("Postgres #{project.dig('database', 'version')}" if project.dig("database", "version")) ].compact
        lines = services.map do |service|
          said = [ service["status"], service["error"].presence ].compact.join(", ")
          "- #{service['name']}: #{said.presence || (service['healthy'] ? 'healthy' : 'unhealthy')}"
        end
        unhealthy = services.count { |service| service["status"].present? && service["status"] != HEALTHY }
        verdict = unhealthy.zero? ? "Every service answers healthy." : "#{unhealthy} of #{services.size} services are not healthy."
        Telemetry.result("How #{project['name'].presence || ref} stands on Supabase now: #{facts.join(', ')}. #{verdict}\n#{lines.join("\n")}",
                         link: page_link(environment_row, ref))
      end

      def get_project_metrics(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        readings = Array(arguments["readings"]).map(&:to_s).presence || (arguments["names"].present? ? [] : READINGS)
        unknown = readings - READINGS
        fail!("Supabase's readings are #{READINGS.join(', ')}, not #{unknown.join(', ')}.") if unknown.any?

        client = api(environment_row)
        first = samples(client.metrics(ref))
        later = readings.include?("cpu") ? sampled_again(client, ref) : nil
        at = Time.current
        charts = readings.filter_map { |reading| chart_of(reading, first, later, at, ref) }
        named = Array(arguments["names"]).map(&:to_s).compact_blank.map { |name| named_line(name, first) }
        text = [ Telemetry.charts_text(charts).presence, *named ].compact.join("\n")
        Telemetry.result(text.presence || "Supabase reported none of those metrics for #{ref}.", link: page_link(environment_row, ref), charts: charts)
      end

      def list_backups(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        found = api(environment_row).backups(ref)
        physical = found["physical_backup_data"].to_h
        earliest, latest = physical.values_at("earliest_physical_backup_date_unix", "latest_physical_backup_date_unix").map { |at| at && Time.zone.at(at).utc.iso8601 }
        pitr = found["pitr_enabled"] ? "Point in time recovery is on#{", from #{earliest} to #{latest}" if earliest && latest}." : "Point in time recovery is off."
        rows = Array(found["backups"]).sort_by { |backup| backup["inserted_at"].to_s }.reverse.first(30).map do |backup|
          "- #{backup['inserted_at']}: #{backup['status']}#{', physical' if backup['is_physical_backup']}"
        end
        text = [ "#{ref}'s backups, newest first. #{pitr}", *rows ].join("\n")
        Telemetry.result(rows.empty? ? "#{ref} has no backups yet. #{pitr}" : text, link: page_link(environment_row, ref, BACKUPS_PAGE))
      end

      def restart_project(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        api(environment_row).restart(ref)
        Telemetry.result("Supabase is restarting #{ref}. get_project_health says when it is back.", link: page_link(environment_row, ref))
      end

      def restore_to_point_in_time(environment_row:, arguments:)
        ref = ref!(environment_row, arguments)
        at = Telemetry.parse_time(arguments["to"]) || fail!("Say the moment to restore to as an ISO 8601 time, such as 2026-10-20T09:30:00Z.")
        client = api(environment_row)
        fail!("Point in time recovery is off for #{ref}, so it cannot be restored to a moment.") unless client.backups(ref)["pitr_enabled"]

        client.restore_to(ref, at)
        Telemetry.result("Supabase is restoring #{ref}'s database to #{at.utc.iso8601}. Every change after that is lost, and the project " \
                         "is unavailable until it is done, which get_project_health says.", link: page_link(environment_row, ref, BACKUPS_PAGE))
      end

      # Any refusal is said in Supabase's words, with what the connection lacks when that is why.
      def call(...)
        super
      rescue SupabaseApi::Refused => error
        fail!(Sentence.all(error.message, "The connection's token may lack the access this needs."))
      rescue SupabaseApi::Error => error
        fail!(error.message)
      end

      private

      def api(environment_row)
        given = Credentials.headers_for(environment_row)["Authorization"].to_s.strip
        fail!("This Supabase connection holds no credentials to reach Supabase's API.") if given.empty?

        SupabaseApi.new(given.match?(/\ABearer\s/i) ? given : "Bearer #{given}")
      end

      # The project a call names, or the one a scoped connection is held to. A scoped one reaches no other.
      def ref!(environment_row, arguments)
        scoped = ConnectionSettings.of(environment_row).field(SCOPED_TO).presence
        asked = arguments["project_id"].to_s.strip.presence
        fail_policy!("This Supabase connection is scoped to project #{scoped}, so it cannot reach #{asked}.") if scoped && asked && asked != scoped

        asked || scoped || fail!("Name the project by its ref, as list_projects or list_branches gives it.")
      end

      def required!(arguments, key) = arguments[key].to_s.strip.presence || fail!("Name the #{key}.")

      # The branch the ref is, from its parent's branches, which say how its newest run ended. The parent is the one the
      # map links the branch to, or the ref itself for a project's default branch. nil when Supabase does not say.
      def latest_of(environment_row, client, ref)
        parent = ResourceMap::Link.facts.joins(:from_resource).includes(:to_resource)
                                  .where(relation: ResourceMap::RELATION_BRANCH_OF,
                                         from_resource: { integration_environment_id: environment_row.id, provider: PROVIDER_KEY,
                                                          kind: ResourceMap::KIND_BRANCH, external_id: ref })
                                  .first&.to_resource&.external_id
        client.branches(parent || ref).find { |branch| branch["project_ref"] == ref }
      rescue SupabaseApi::Error
        nil
      end

      def run_of(run, ref, latest, site, parts: false)
        steps = Array(run["run_steps"])
        status = run_status(run, steps, latest)
        ended = steps.filter_map { |step| Capabilities::RunHistory.time(step["updated_at"]) }.max
        failed = steps.find { |step| step["status"].to_s.casecmp?("dead") }
        Capabilities::History::Run.new(
          id: run["id"], name: ACTION_RUN, status: status, started_at: Capabilities::RunHistory.time(run["created_at"]),
          finished_at: (ended if Capabilities::History::FINISHED.include?(status)), url: (MapReaders::Supabase.page(site, ref, BRANCHES_PAGE) if site),
          detail: [ ("#{latest['git_branch']}" if latest&.dig("git_branch").present?), ("stopped at #{failed['name']}" if failed),
                    ("branch #{latest['status'].downcase.tr('_', ' ')}" if newest?(run, latest)) ].compact.join(", ").presence,
          parts: (steps.map { |step| part_of(step, ref, run["id"]) } if parts)
        )
      end

      # A step still going or one that died says how the run stands. Once every step exited, the branch's status says how
      # its newest run ended, and an older one counts as finished well.
      def run_status(run, steps, latest)
        states = steps.map { |step| Capabilities::History.status(step["status"], STEP_STATES) }
        return Capabilities::History::FAILED if states.include?(Capabilities::History::FAILED)
        return Capabilities::History::RUNNING if states.empty? || states.any? { |state| state != Capabilities::History::SUCCEEDED }
        return Capabilities::History.status(latest["status"], BRANCH_STATES) if newest?(run, latest)

        Capabilities::History::SUCCEEDED
      end

      def newest?(run, latest) = latest.present? && latest["latest_check_run_id"].present? && latest["latest_check_run_id"].to_s == run["check_run_id"].to_s

      def part_of(step, ref, run_id)
        status = Capabilities::History.status(step["status"], STEP_STATES)
        Capabilities::History::Part.new(
          id: step["name"], name: step["name"], status: status, started_at: Capabilities::RunHistory.time(step["created_at"]),
          finished_at: (Capabilities::RunHistory.time(step["updated_at"]) if Capabilities::History::FINISHED.include?(status)),
          log: { Capabilities::History::LOG_TOOL => RUN_LOGS, Capabilities::History::LOG_ARGUMENTS => { "project_id" => ref, "run_id" => run_id } }
        )
      end

      # One sample a line of the Prometheus text format: the name, its labels and its value.
      Sample = Data.define(:name, :labels, :value)
      LINE = /\A(?<name>[a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{(?<labels>.*)\})?\s+(?<value>\S+)/
      LABEL = /(\w+)="((?:[^"\\]|\\.)*)"/

      def samples(text)
        text.to_s.each_line.filter_map do |line|
          next if line.start_with?("#")

          found = line.strip.match(LINE) || next
          value = Float(found[:value], exception: false) || next
          Sample.new(name: found[:name], labels: found[:labels].to_s.scan(LABEL).to_h, value: value)
        end
      end

      def sampled_again(client, ref)
        sleep CPU_SAMPLE_SECONDS
        samples(client.metrics(ref))
      end

      def database_host(found, name) = found.select { |sample| sample.name == name && sample.labels["service_type"].in?([ nil, DB_SERVICE ]) }

      def chart_of(reading, first, later, at, ref)
        value = case reading
        when "cpu" then cpu_busy(first, later)
        when "memory" then memory_used(first)
        when "disk" then return disk_chart(first, at, ref)
        end
        series = value.nil? ? [] : [ Telemetry::Series.new(label: ref, points: [ [ at, value.round(1) ] ]) ]
        Telemetry::Chart.new(title: "#{reading} of #{ref}", unit: "%", series: series, from: at, to: at)
      end

      # The share of CPU time not idle between the two readings, across every CPU.
      def cpu_busy(first, later)
        return if later.nil?

        totals = ->(found) { database_host(found, "node_cpu_seconds_total").group_by { |sample| sample.labels["mode"] == "idle" }.transform_values { |each| each.sum(&:value) } }
        before = totals.call(first)
        after = totals.call(later)
        idle = after.fetch(true, 0) - before.fetch(true, 0)
        busy = after.fetch(false, 0) - before.fetch(false, 0)
        idle + busy > 0 ? busy / (idle + busy) * 100 : nil
      end

      def memory_used(found)
        total = database_host(found, "node_memory_MemTotal_bytes").sum(&:value)
        available = database_host(found, "node_memory_MemAvailable_bytes").sum(&:value)
        total.positive? ? (total - available) / total * 100 : nil
      end

      # How full each disk is, one series a mount point.
      def disk_chart(found, at, ref)
        sizes = database_host(found, "node_filesystem_size_bytes").index_by { |sample| sample.labels["mountpoint"] }
        series = database_host(found, "node_filesystem_avail_bytes").filter_map do |sample|
          size = sizes[sample.labels["mountpoint"]]&.value
          next unless size&.positive?

          Telemetry::Series.new(label: sample.labels["mountpoint"].to_s, points: [ [ at, ((size - sample.value) / size * 100).round(1) ] ])
        end
        Telemetry::Chart.new(title: "disk of #{ref}", unit: "%", series: series, from: at, to: at)
      end

      def named_line(name, found)
        matching = found.select { |sample| sample.name == name }
        return "#{name}: Supabase did not report it." if matching.empty?

        values = matching.first(20).map { |sample| "#{sample.labels.except('supabase_project_ref').map { |key, value| "#{key}=#{value}" }.join(' ').presence || 'value'} #{sample.value}" }
        "#{name}: #{values.join(', ')}#{" and #{matching.size - 20} more" if matching.size > 20}"
      end

      def page_link(environment_row, ref, path = nil)
        site = ConnectionSettings.of(environment_row).site
        site && Telemetry::Link.new(provider: PROVIDER, url: MapReaders::Supabase.page(site, ref, path))
      end
    end
  end
end
