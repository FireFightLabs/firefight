module Integrations
  module Packs
    # Modal for one environment of a workspace: its apps, their logs and deployment history, and the changes Modal's CLI
    # makes to a deployed app (modal app rollback and rollover, and Function.update_autoscaler), read and made with a
    # Modal token. Each tool makes the calls the matching command of Modal's open source client makes
    # (github.com/modal-labs/modal-client, py/modal/cli/app.py and py/modal/_logs.py), through Integrations::ModalApi.
    class Modal < NativePack
      # The environment row's credentials, which only this pack reads.
      TOKEN_ID = "token_id".freeze
      TOKEN_SECRET = "token_secret".freeze
      ENVIRONMENT = "environment".freeze

      PROVIDER = "Modal".freeze
      PROVIDER_KEY = "modal".freeze
      # An app's page is <site>/id/<app id>, the address modal app dashboard opens (py/modal/cli/app.py).
      APP_PAGE = "id".freeze
      # An app id as resolve_app_identifier tells it from a name (py/modal/cli/app.py).
      APP_ID = /\Aap-[a-zA-Z0-9]{22}\z/

      DEFAULT_MINUTES = 60
      MAX_MINUTES = (ModalApi::MAX_FETCH_RANGE / 60).to_i
      LOG_LIMIT = 200
      MAX_LOG_LIMIT = 500
      HISTORY_LIMIT = 10
      MAX_HISTORY_LIMIT = 50
      # The streams modal app logs --source takes, and the file descriptors they are (py/modal/cli/_logs.py).
      SOURCES = { "stdout" => :FILE_DESCRIPTOR_STDOUT, "stderr" => :FILE_DESCRIPTOR_STDERR, "system" => :FILE_DESCRIPTOR_INFO }.freeze
      DEPLOYED = :APP_STATE_DEPLOYED
      # How modal app list names each state (APP_STATE_TO_MESSAGE in py/modal/cli/app.py).
      STATES = {
        APP_STATE_DEPLOYED: "deployed", APP_STATE_DETACHED: "ephemeral (detached)", APP_STATE_DETACHED_DISCONNECTED: "ephemeral (detached)",
        APP_STATE_DISABLED: "disabled", APP_STATE_EPHEMERAL: "ephemeral", APP_STATE_INITIALIZING: "initializing", APP_STATE_STOPPED: "stopped",
        APP_STATE_STOPPING: "stopping"
      }.freeze
      DEPLOYMENT_TYPES = { DEPLOYMENT_TYPE_ROLLBACK: "a rollback", DEPLOYMENT_TYPE_ROLLOVER: "a rollover", DEPLOYMENT_TYPE_PROMOTION: "a promotion",
                           DEPLOYMENT_TYPE_STAGED: "staged" }.freeze
      # The autoscaler settings update_autoscaler takes (Function.update_autoscaler, py/modal/_functions.py).
      AUTOSCALER = %w[min_containers max_containers buffer_containers scaledown_window].freeze
      VERSION = /\Av?(?<number>[1-9]\d*)\z/

      RANGE = {
        "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
        "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
        "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
      }.freeze
      APP = { "type" => "string", "description" => "An app, by its name or its id (ap-...), as list_apps shows it" }.freeze

      tool :list_apps,
           description: "The apps in the Modal environment for this connection that run, are deployed or stopped recently, with " \
                        "each one's state and how many containers it runs now. Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_app,
           description: "How one Modal app stands now: its state, the version deployed, when and by whom, how many containers run, " \
                        "and its functions and servers with each one's GPU, schedule and whether it serves the web",
           params_schema: { "type" => "object", "properties" => { "app" => APP }, "required" => [ "app" ] },
           read_only: true

      tool :app_logs,
           description: "Log lines of one Modal app, newest first, at most #{MAX_LOG_LIMIT}. Filter by text, by function, or by " \
                        "source. stdout and stderr are what the code prints, and system is what Modal says about its containers, such as " \
                        "a crash, an out of memory kill or a timeout. Without a source every one is read",
           params_schema: {
             "type" => "object",
             "properties" => {
               "app" => APP,
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "source" => { "type" => "string", "enum" => SOURCES.keys, "description" => "Which output (optional, all of them)" },
               "function" => { "type" => "string", "description" => "Only this function or server, by its name in describe_app (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             },
             "required" => [ "app" ]
           },
           read_only: true

      tool :deployment_history,
           description: "The versions of one Modal app, newest first: when each was deployed and by whom, the commit it came from, " \
                        "and whether it was a rollback or a rollover. rollback_app takes the version. Use it to see what changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => { "app" => APP, "limit" => { "type" => "integer", "description" => "At most this many versions (optional, #{HISTORY_LIMIT})" } },
             "required" => [ "app" ]
           },
           read_only: true

      tool :rollback_app,
           description: "Put a deployed Modal app back on an earlier version. Modal deploys it again as a new version with the " \
                        "functions and settings of the one asked for. Modal offers rollbacks on its Team and Enterprise plans",
           params_schema: {
             "type" => "object",
             "properties" => {
               "app" => APP,
               "version" => { "type" => "string", "description" => "The version to go back to, such as v5, as deployment_history shows it (optional, the one before the current)" }
             },
             "required" => [ "app" ]
           },
           read_only: false

      tool :rollover_app,
           description: "Replace every container of a deployed Modal app with fresh ones on the same version, for containers stuck " \
                        "in a bad state or holding a secret or connection that went stale. Old containers finish what they hold first",
           params_schema: { "type" => "object", "properties" => { "app" => APP }, "required" => [ "app" ] },
           read_only: false

      tool :update_autoscaler,
           description: "Change how one function of a Modal app scales: the containers it keeps running, the most it may run, the " \
                        "spare ones it keeps while busy, and how long an idle one waits before it stops. What is left out keeps its " \
                        "value. The next deployment of the app puts back what its code says",
           params_schema: {
             "type" => "object",
             "properties" => {
               "app" => APP,
               "function" => { "type" => "string", "description" => "The function, by its name in describe_app" },
               "min_containers" => { "type" => "integer", "description" => "Containers to keep running even with no work (optional)" },
               "max_containers" => { "type" => "integer", "description" => "The most containers it may run at once (optional)" },
               "buffer_containers" => { "type" => "integer", "description" => "Spare containers to keep while it is busy (optional)" },
               "scaledown_window" => { "type" => "integer", "description" => "Seconds an idle container waits before it stops (optional)" }
             },
             "required" => %w[app function]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: TOKEN_ID, label: "Token ID", secret: false, placeholder: "ak-...",
                              hint: "The id of a Modal token. A service user's token suits a team, since it outlives any one person. Create one in Modal under Settings, Service users."),
          CredentialField.new(key: TOKEN_SECRET, label: "Token secret", secret: true, placeholder: "as-...",
                              hint: "The secret Modal shows once, when you create the token.")
        ]
      end

      # Reads the workspace and the environment's apps with the token, so a wrong token or environment is said on the form
      # before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        token_id, token_secret = values.values_at(TOKEN_ID, TOKEN_SECRET).map { |value| value.to_s.strip }
        environment = fields.to_h.stringify_keys[ENVIRONMENT].to_s.strip
        return "Enter the token id." if token_id.empty?
        return "Paste the token secret." if token_secret.empty?

        api = ModalApi.new(token_id, token_secret)
        api.workspace
        api.apps(environment)
        nil
      rescue ModalApi::NotFound
        "Modal has no environment called #{environment} in this workspace. Check its name, or leave it empty for the default."
      rescue ModalApi::Error => error
        Sentence.join("Modal refused this token", error)
      end

      def self.store_credentials!(environment_row, values)
        [ TOKEN_ID, TOKEN_SECRET ].each { |key| environment_row.store_credential!(key, values[key].to_s.strip) }
      end

      def list_apps(environment_row:, arguments:)
        apps = api(environment_row).apps(environment(environment_row)).sort_by { |app| [ -app.n_running_tasks, -app.created_at ] }
        where = environment(environment_row).presence || "the default environment"
        return Telemetry.result("Modal has no apps in #{where}.", link: nil) if apps.empty?

        rows = apps.map do |app|
          [ "#{app.description} (#{app.app_id})", state_of(app.state), "#{app.n_running_tasks} containers running", "created #{at(app.created_at)}",
            ("stopped #{at(app.stopped_at)}" if app.stopped_at.positive?), "page #{app_page(environment_row, app.app_id)}" ].compact.join(", ")
        end
        Telemetry.result("#{rows.size} apps in #{where}, those running most containers first, each with its page in Modal.\n#{rows.join("\n")}", link: nil)
      end

      def describe_app(environment_row:, arguments:)
        app_id = find_app(environment_row, arguments["app"]).first
        answer = api(environment_row).info(app_id)
        app = answer.info
        lifecycle = app.lifecycle
        running = api(environment_row).containers(app_id, environment(environment_row)).size
        lines = [
          "#{app.description} (#{app_id}), #{state_of(lifecycle.app_state)}",
          ("Deployed version v#{lifecycle.version} at #{at(lifecycle.deployed_at)}#{" by #{lifecycle.deployed_by}" if lifecycle.deployed_by.present?}" if lifecycle.deployed_at.positive?),
          "Created at #{at(lifecycle.created_at)}#{" by #{lifecycle.created_by}" if lifecycle.created_by.present?}",
          ("Stopped at #{at(lifecycle.stopped_at)}#{" by #{lifecycle.stopped_by}" if lifecycle.stopped_by.present?}. A stopped app cannot be started again, only deployed anew." if lifecycle.stopped_at.positive?),
          "Containers running now: #{running}",
          entries("Functions", app.functions, answer.function_info_summaries),
          entries("Servers", app.servers, answer.function_info_summaries)
        ]
        Telemetry.result(lines.compact.join("\n"), link: app_link(environment_row, app_id))
      end

      def app_logs(environment_row:, arguments:)
        app_id, app = find_app(environment_row, arguments["app"])
        started, ended = Telemetry.range(arguments, default_minutes: DEFAULT_MINUTES, max_minutes: MAX_MINUTES)
        limit = Capabilities::Answers.limit(arguments, MAX_LOG_LIMIT, default: LOG_LIMIT)
        source = arguments["source"].presence
        fail!("source must be one of #{SOURCES.keys.join(', ')}.") if source && !SOURCES.key?(source)

        functions = function_names(environment_row, app_id)
        function_id = function_id_of(functions, arguments["function"]) if arguments["function"].present?
        batches = api(environment_row).logs(app_id, since: started, upto: ended, limit: limit, source: SOURCES.fetch(source, :FILE_DESCRIPTOR_UNSPECIFIED),
                                            search_text: arguments["text"], function_id: function_id)
        lines = batches.flat_map do |batch|
          origin = functions.key(batch.function_id) || batch.task_id
          batch.items.filter_map do |item|
            text = item.data.to_s.strip
            next if text.empty? || (arguments["exclude"].present? && text.include?(arguments["exclude"]))

            Telemetry::LogLine.new(at: Time.zone.at(item.timestamp).utc, source: [ origin, item.container_id.presence ].compact.join(" "), text: text)
          end
        end.sort_by(&:at).reverse
        asked = "#{app} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        Telemetry.result(Telemetry.logs_text(lines, asked: asked, limit: limit), link: app_link(environment_row, app_id))
      end

      def deployment_history(environment_row:, arguments:)
        app_id, app = find_app(environment_row, arguments["app"])
        limit = Capabilities::Answers.limit(arguments, MAX_HISTORY_LIMIT, default: HISTORY_LIMIT)
        versions = api(environment_row).history(app_id).app_deployment_histories.sort_by { |each| -each.version }.first(limit)
        return Telemetry.result("#{app} has no deployments.", link: app_link(environment_row, app_id)) if versions.empty?

        rows = versions.map { |version| version_line(version) }
        Telemetry.result("Latest #{rows.size} versions of #{app}, newest first, the first is live. rollback_app takes a version.\n#{rows.join("\n")}", link: app_link(environment_row, app_id))
      end

      # The CLI refuses either change for an app that is not deployed, and so does this, before anything is sent.
      def rollback_app(environment_row:, arguments:)
        app_id, app = find_deployed(environment_row, arguments["app"])
        asked = arguments["version"].to_s.strip
        match = asked.match(VERSION)
        fail!("version must be a version number such as v5, as deployment_history shows it.") if asked.present? && match.nil?

        version = match ? match[:number].to_i : -1
        answer = begin
          api(environment_row).rollback(app_id, version)
        rescue ModalApi::Refused => error
          fail!(Sentence.join("Modal refused the rollback", error,
                              after: "Modal offers rollbacks on its Team and Enterprise plans, and only to a version it still keeps"))
        end
        what = match ? "v#{version}" : "the version before the one that was live"
        Telemetry.result("#{app} is deployed again with #{what}, as a new version.#{warnings(answer)}", link: change_link(environment_row, answer, app_id))
      end

      def rollover_app(environment_row:, arguments:)
        app_id, app = find_deployed(environment_row, arguments["app"])
        answer = api(environment_row).rollover(app_id)
        Telemetry.result("#{app} is rolling over to fresh containers on the same version. Running containers finish what they " \
                         "hold, then stop.#{warnings(answer)}", link: change_link(environment_row, answer, app_id))
      end

      def update_autoscaler(environment_row:, arguments:)
        app_id, app = find_deployed(environment_row, arguments["app"])
        settings = AUTOSCALER.filter_map do |name|
          next if arguments[name].nil? || arguments[name] == ""

          value = Integer(arguments[name], exception: false)
          fail!("#{name} must be a whole number, 0 or more.") unless value && value >= 0
          [ name.to_sym, value ]
        end.to_h
        fail!("Say what to change: #{AUTOSCALER.join(', ')}.") if settings.empty?

        function = arguments["function"].to_s.strip
        function_id = function_id_of(function_names(environment_row, app_id), function)
        current = api(environment_row).update_autoscaler(function_id, settings)
        now = AUTOSCALER.filter_map { |name| "#{name} #{current.public_send(name)}" if current.public_send(:"has_#{name}?") }
        Telemetry.result("#{function} in #{app} now scales with #{now.presence&.join(', ') || "Modal's defaults"}. The next deployment of " \
                         "#{app} puts back what its code says.", link: app_link(environment_row, app_id))
      end

      # The environment's deployed apps on the map, each with its page, its version and the commit it was deployed from.
      def map_of(environment_row)
        api = api(environment_row)
        workspace = api.workspace
        gaps = []
        resources = api.apps(environment(environment_row)).select { |app| app.state == DEPLOYED }.map do |app|
          where = environment(environment_row).presence || app.metadata&.environment_name.presence
          details = { "version" => ("v#{app.metadata.lifecycle.version}" if app.metadata&.lifecycle), "running_containers" => app.n_running_tasks }
          begin
            latest = api.history(app.app_id).app_deployment_histories.max_by(&:version)
            details[ResourceMap::DEPLOYED_COMMIT] = latest&.commit_info&.commit_hash.presence
          rescue Integrations::RateLimited
            raise
          rescue ModalApi::Error => error
            # Only the commit is missing. The app itself was read, so nothing is held back.
            gaps << ResourceMap::Gap.new(text: Sentence.join("The deployment history of #{app.description} could not be read", error), kinds: [])
          end
          ResourceMap::Found.new(provider: PROVIDER_KEY, account: [ workspace, where ].compact.join("/"), kind: ResourceMap::KIND_SERVICE,
                                 external_id: app.app_id, name: app.description.presence || app.app_id, status: state_of(app.state),
                                 url: app_page(environment_row, app.app_id), details: details.compact)
        end
        ResourceMap::Snapshot.new(resources: resources, links: [], gaps: gaps)
      end

      def check_health!(environment_row)
        api(environment_row).workspace
      rescue ModalApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        settings = ConnectionSettings.of(environment_row)
        token_id, token_secret = settings.credential(TOKEN_ID), settings.credential(TOKEN_SECRET)
        fail! "This environment has no Modal token. Reconnect it on the Integrations page." if token_id.nil? || token_secret.nil?

        @api ||= ModalApi.new(token_id, token_secret)
      end

      def environment(environment_row) = ConnectionSettings.of(environment_row).field(ENVIRONMENT).to_s

      # The app's id and name, from either, as resolve_app_identifier finds it: an id directly, a name as the app
      # deployed under it now, or the one of that name stopped most recently.
      def find_app(environment_row, asked)
        wanted = asked.to_s.strip
        fail!("Say which app, by name or id. list_apps shows them.") if wanted.empty?

        if wanted.match?(APP_ID)
          api(environment_row).lifecycle(wanted)
          return [ wanted, name_of(environment_row, wanted) ]
        end

        found = api(environment_row).deployed(wanted, environment(environment_row))
        app_id = found.app_id.presence || found.previous_app_id.presence
        fail!("No app called #{wanted} in #{environment(environment_row).presence || 'the default environment'}. list_apps shows what there is.") unless app_id
        [ app_id, wanted ]
      rescue ModalApi::NotFound
        fail!("No app #{wanted} in this Modal workspace. list_apps shows what there is.")
      end

      def find_deployed(environment_row, asked)
        app_id, app = find_app(environment_row, asked)
        state = api(environment_row).lifecycle(app_id).app_state
        fail!("#{app} is #{state_of(state)}, not deployed, so Modal cannot change it this way.") unless state == DEPLOYED

        [ app_id, app ]
      end

      def name_of(environment_row, app_id) = api(environment_row).info(app_id).info.description.presence || app_id

      # Function and server names to their ids.
      def function_names(environment_row, app_id)
        app = api(environment_row).info(app_id).info
        app.functions.to_h.merge(app.servers.to_h)
      end

      def function_id_of(functions, name)
        functions[name.to_s.strip] || fail!("No function or server called #{name} in this app. It has #{functions.keys.sort.join(', ').presence || 'none'}.")
      end

      def entries(title, map, summaries)
        return nil if map.to_h.empty?

        rows = map.to_h.sort.map do |name, function_id|
          summary = summaries[function_id]
          next "  #{name} (#{function_id})" unless summary

          hardware = summary.gpu_config.map { |gpu| "#{gpu.count} x #{gpu.gpu_type.presence || gpu.type.to_s.delete_prefix('GPU_TYPE_')} GPU" }.presence || [ "CPU" ]
          [ "  #{name} (#{function_id})", hardware.join(" and "), ("web" if summary.web_function), schedule(summary.schedule),
            ("open to anyone, no proxy auth" if summary.has_requires_proxy_auth? && !summary.requires_proxy_auth) ].compact.join(", ")
        end
        "#{title} (#{rows.size}):\n#{rows.join("\n")}"
      end

      def schedule(schedule)
        return nil unless schedule
        return "runs on cron #{schedule.cron.cron_string} (#{schedule.cron.timezone.presence || 'UTC'})" if schedule.cron

        period = schedule.period
        return nil unless period

        parts = %w[years months weeks days hours minutes seconds].filter_map { |unit| "#{period.public_send(unit).to_s.delete_suffix('.0')} #{unit}" if period.public_send(unit).positive? }
        "runs every #{parts.join(' ')}" if parts.any?
      end

      def version_line(version)
        commit = version.commit_info
        [ "v#{version.version}", at(version.deployed_at), ("by #{version.deployed_by}" if version.deployed_by.present?),
          DEPLOYMENT_TYPES[version.deployment_type], ("back to v#{version.rollback_version}" if version.rollback_version.positive?),
          ("commit #{commit.commit_hash.first(12)}#{' with uncommitted changes' if commit.dirty}#{" on #{commit.branch}" if commit.branch.present?}" if commit&.commit_hash.present?),
          ("tag #{version.tag}" if version.tag.present?), ("client #{version.client_version}" if version.client_version.present?) ].compact.join(", ")
      end

      def warnings(answer)
        said = answer.server_warnings.map(&:message).compact_blank
        said.any? ? "\nModal warned: #{said.join(' ')}" : ""
      end

      def state_of(state) = STATES.fetch(state.is_a?(Integer) ? ModalApi::Proto::AppState.lookup(state) : state, "unknown")

      def at(seconds) = seconds.to_f.positive? ? Time.zone.at(seconds.to_f).utc.iso8601 : "unknown"

      def app_link(environment_row, app_id) = Telemetry::Link.new(provider: PROVIDER, url: app_page(environment_row, app_id))

      def app_page(environment_row, app_id) = "#{ConnectionSettings.of(environment_row).site.to_s.chomp('/')}/#{APP_PAGE}/#{Http.segment(app_id)}"

      # The deployment's page Modal returns with a change, or the app's page when it returns none.
      def change_link(environment_row, answer, app_id) = answer.url.present? ? Telemetry::Link.new(provider: PROVIDER, url: answer.url) : app_link(environment_row, app_id)
    end
  end
end
