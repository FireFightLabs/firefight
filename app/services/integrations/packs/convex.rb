module Integrations
  module Packs
    # One Convex deployment per environment: how it stands, its function logs and errors, and what was pushed to it, read
    # with a deploy key the workspace creates in Convex. Every tool reads. Convex documents no rollback, restart or scale
    # for a deployment, so none is offered.
    class Convex < NativePack
      # The environment row's credentials, which only this pack reads.
      DEPLOYMENT_URL = "deployment_url".freeze
      DEPLOY_KEY = "deploy_key".freeze

      PROVIDER = "Convex".freeze
      PROVIDER_KEY = "convex".freeze
      # A deployment's page is <site>/d/<deployment name>, as the CLI's deploymentDashboardUrlPage builds it
      # (npm-packages/convex/src/cli/lib/dashboard.ts).
      DEPLOYMENT_PAGE = "d".freeze
      # Only a deployment Convex hosts is reached, since Firefight sends the deploy key wherever this points.
      CLOUD_URL = %r{\Ahttps://(?<name>[a-z0-9-]+)(\.[a-z0-9-]+)*\.convex\.cloud/?\z}
      KIND_CLOUD = "cloud".freeze
      KIND_SELF_HOSTED = "selfHosted".freeze

      # Function executions as the logs endpoint describes them (function-logs-openapi.json, FunctionExecutionJson).
      COMPLETION = "Completion".freeze
      # An execution's timestamp is in seconds and a log line's in milliseconds, as the CLI reads them (logs.ts).
      LEVEL_ERROR = "ERROR".freeze
      # The audit log actions that put new code or schema on the deployment (DeploymentAuditLogEventResponse).
      PUSHES = %w[push_config push_config_with_components build_indexes].freeze
      # The ones that change whether it runs at all.
      PAUSE = "pause_deployment".freeze
      UNPAUSE = "unpause_deployment".freeze
      STATE_CHANGES = [ PAUSE, UNPAUSE, *%w[change_deployment_state change_system_stop_state usage_limit_exceeded change_usage_limit_stop_state] ].freeze
      # Firefight's words for a deployment's status on the map.
      RUNNING = "running".freeze
      PAUSED = "paused".freeze

      # Who an audit log event names as having acted (AuditLogActor).
      ACTOR_MEMBER = "member".freeze
      ACTOR_TOKEN = "token".freeze
      ACTOR_SYSTEM = "system".freeze

      LOG_LIMIT = 200
      ERROR_GROUPS = 20
      PUSH_LIMIT = 10
      PUSH_DAYS = 30
      MAX_PUSH_DAYS = 90
      STATE_DAYS = 7
      AUDIT_PAGES = 10
      METADATA_LIMIT = 400

      RANGE = Capabilities::RANGE
      FUNCTION = { "type" => "string", "description" => "Only executions of functions whose path contains this, such as messages:send (optional)" }.freeze

      tool :deployment_status,
           description: "Who this Convex deployment is (project, type, id), the URLs it answers on, and whether it was paused, " \
                        "or stopped by a usage limit or by Convex, in the last #{STATE_DAYS} days, from its audit log",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_logs,
           description: "Function log lines of the deployment, newest first, at most #{LOG_LIMIT}: what each query, mutation, " \
                        "action and HTTP action printed, and the error of each execution that failed. Filter by text, by " \
                        "function or to failures only. The deployment keeps only its recent executions, so a range older " \
                        "than that comes back short, and the answer says so",
           params_schema: {
             "type" => "object",
             "properties" => {
               "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
               "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
               "function" => FUNCTION,
               "failures_only" => { "type" => "boolean", "description" => "Only executions that threw an error (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many lines (optional, #{LOG_LIMIT})" },
               **RANGE
             }
           },
           read_only: true

      tool :function_errors,
           description: "Functions that failed, grouped by function and error with how often each happened and when last, " \
                        "worst first, and whether Convex retried them. Read from the executions the deployment still keeps",
           params_schema: {
             "type" => "object",
             "properties" => {
               "text" => { "type" => "string", "description" => "Only errors containing this text (optional)" },
               "function" => FUNCTION,
               "limit" => { "type" => "integer", "description" => "At most this many groups (optional, #{ERROR_GROUPS})" },
               **RANGE
             }
           },
           read_only: true

      tool :recent_pushes,
           description: "Code and schema pushed to the deployment, newest first, from its audit log: when, by whom (a person " \
                        "in the dashboard, or a deploy key or token) and what Convex recorded about it. Use it to see what " \
                        "changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "limit" => { "type" => "integer", "description" => "At most this many pushes (optional, #{PUSH_LIMIT})" },
               "days" => { "type" => "integer", "description" => "How many days back to look (optional, #{PUSH_DAYS}, at most #{MAX_PUSH_DAYS})" }
             }
           },
           read_only: true

      def self.credential_fields
        [
          CredentialField.new(key: DEPLOY_KEY, label: "Deploy key", secret: true, placeholder: "prod:happy-animal-123|...",
                              hint: "A deploy key for this deployment, created under Settings, Deploy keys in the Convex dashboard.")
        ]
      end

      # Reads the deployment with the key, so a wrong URL or key is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil, fields: {})
        url = fields.to_h.stringify_keys[DEPLOYMENT_URL].to_s.strip.chomp("/")
        key = values[DEPLOY_KEY].to_s.strip
        return "Enter the deployment URL." if url.empty?
        return "Enter a deployment URL that ends in convex.cloud, as the Convex dashboard shows it." unless url.match?(CLOUD_URL)
        return "Paste a deploy key." if key.empty?

        ConvexApi.new(url, key).deployment_info
        nil
      rescue ConvexApi::Error => error
        Sentence.join("Convex refused this deployment URL or deploy key", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(DEPLOY_KEY, values[DEPLOY_KEY].to_s.strip)
      end

      def deployment_status(environment_row:, arguments:)
        api = api(environment_row)
        info = api.deployment_info
        lines = [ identity_line(environment_row, info) ]
        lines << begin
          urls = api.canonical_urls
          "Answers on #{urls['convexCloudUrl']} (functions) and #{urls['convexSiteUrl']} (HTTP actions)"
        rescue Integrations::RateLimited
          raise
        rescue ConvexApi::Error => error
          Sentence.join("Its URLs could not be read", error)
        end
        lines << state_lines(api)
        Telemetry.result(lines.join("\n"), link: dashboard_link(environment_row))
      end

      def search_logs(environment_row:, arguments:)
        started, ended = Capabilities::Answers.range(arguments)
        limit = Capabilities::Answers.limit(arguments, LOG_LIMIT)
        read = executions(environment_row, started, ended)
        executions = of_function(read, arguments["function"])
        executions = executions.select { |execution| failed?(execution) } if arguments["failures_only"]
        lines = executions.flat_map { |execution| lines_of(execution) }
                          .select { |line| line.at.between?(started, ended) && kept?(line.text, arguments) }
                          .sort_by(&:at).reverse.first(limit)
        asked = "#{deployment_name(environment_row)} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
        text = [ Telemetry.logs_text(lines, asked: asked, limit: limit), window_note(read, started) ].compact.join("\n")
        Telemetry.result(text, link: dashboard_link(environment_row))
      end

      def function_errors(environment_row:, arguments:)
        started, ended = Capabilities::Answers.range(arguments)
        read = executions(environment_row, started, ended)
        executions = of_function(read, arguments["function"])
        failed = executions.select { |execution| failed?(execution) }
        failed = failed.select { |execution| execution["error"].to_s.downcase.include?(arguments["text"].to_s.downcase) } if arguments["text"].present?
        groups = failed.group_by { |execution| [ execution["identifier"].to_s, execution["error"].to_s.lines.first.to_s.strip ] }
        rows = groups.sort_by { |_, members| -members.size }.first(Capabilities::Answers.limit(arguments, ERROR_GROUPS)).map do |(function, error), members|
          last = members.filter_map { |execution| executed_at(execution) }.max
          retried = members.count { |execution| execution["willRetry"] }
          [ "#{members.size} times", "#{members.first['udfType']} #{function}", "last #{last&.utc&.iso8601 || 'unknown'}",
            ("#{retried} will be retried" if retried.positive?), error.truncate(Telemetry::LOG_CELL_LIMIT) ].compact.join(", ")
        end
        window = "#{started.utc.iso8601} to #{ended.utc.iso8601}"
        text = if rows.empty?
          "No function of #{deployment_name(environment_row)} failed from #{window}, out of #{executions.size} executions read."
        else
          "#{failed.size} failed executions of #{executions.size} read on #{deployment_name(environment_row)} from #{window}, in " \
            "#{groups.size} groups, most frequent first.\n#{rows.join("\n")}"
        end
        Telemetry.result([ text, window_note(read, started) ].compact.join("\n"), link: dashboard_link(environment_row))
      end

      def recent_pushes(environment_row:, arguments:)
        days = arguments["days"].to_i.positive? ? [ arguments["days"].to_i, MAX_PUSH_DAYS ].min : PUSH_DAYS
        events, complete = audit_events(api(environment_row), days.days.ago)
        pushes = events.select { |event| PUSHES.include?(event["action"]) }.reverse.first(Capabilities::Answers.limit(arguments, PUSH_LIMIT))
        link = dashboard_link(environment_row)
        cut = complete ? "" : " Only the first #{AUDIT_PAGES * ConvexApi::AUDIT_PAGE} audit log events were read, so later pushes may be missing."
        return Telemetry.result("Nothing was pushed to #{deployment_name(environment_row)} in the last #{days} days.#{cut}", link: link) if pushes.empty?

        rows = pushes.map { |event| event_line(event) }
        text = "Latest #{rows.size} pushes to #{deployment_name(environment_row)}, newest first. Convex has no rollback, so undoing " \
               "one means pushing the earlier code again.#{cut}\n#{rows.join("\n")}"
        Telemetry.result(text, link: link)
      end

      # The deployment on the resource map, under its project, with its page in the Convex dashboard.
      def map_of(environment_row)
        api = api(environment_row)
        info = api.deployment_info
        name = deployment_name(environment_row)
        cloud = info["kind"] == KIND_CLOUD
        found = ResourceMap::Found.new(
          provider: PROVIDER_KEY, account: cloud ? info["projectSlug"].presence || info["projectId"].to_s : KIND_SELF_HOSTED,
          kind: ResourceMap::KIND_SERVICE, external_id: name, name: name, status: map_status(api), url: dashboard_link(environment_row)&.url,
          details: { "project" => info["projectName"], "type" => info["deploymentType"], "reference" => info["reference"] }.compact
        )
        ResourceMap::Snapshot.new(resources: [ found ], links: [], gaps: [])
      end

      def check_health!(environment_row)
        api(environment_row).deployment_info
      rescue ConvexApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        url = deployment_url(environment_row)
        key = ConnectionSettings.of(environment_row).credential(DEPLOY_KEY).to_s
        fail! "This environment has no Convex deploy key. Reconnect it on the Integrations page." if key.blank?
        fail! "This environment's Convex deployment URL does not end in convex.cloud. Reconnect it on the Integrations page " \
              "with the URL Settings shows in the Convex dashboard." unless url.match?(CLOUD_URL)

        ConvexApi.new(url, key)
      end

      def deployment_url(environment_row) = ConnectionSettings.of(environment_row).field(DEPLOYMENT_URL).to_s.chomp("/")

      def deployment_name(environment_row) = deployment_url(environment_row)[CLOUD_URL, :name].to_s

      def dashboard_link(environment_row)
        name = deployment_name(environment_row)
        name.present? ? Telemetry::Link.new(provider: PROVIDER, url: "#{ConnectionSettings.of(environment_row).site.to_s.chomp('/')}/#{DEPLOYMENT_PAGE}/#{Http.segment(name)}") : nil
      end


      def identity_line(environment_row, info)
        return "#{deployment_name(environment_row)} is a self-hosted Convex deployment." unless info["kind"] == KIND_CLOUD

        [ "#{deployment_name(environment_row)}, the #{info['deploymentType']} deployment of project #{info['projectName'] || info['projectSlug']}",
          ("reference #{info['reference']}" if info["reference"].present?), "deployment id #{info['id']}", "team id #{info['teamId']}" ].compact.join(", ")
      end

      # How the deployment stands, from its latest pause or unpause in the audit log's last STATE_DAYS days, running when
      # there is none, as state_lines says. Any other state change carries metadata Convex does not publish, so it is not
      # read as a status, and neither is an audit log that cannot be read.
      def map_status(api)
        events, _complete = audit_events(api, STATE_DAYS.days.ago)
        latest = events.select { |event| STATE_CHANGES.include?(event["action"]) }.last
        return RUNNING if latest.nil?

        { PAUSE => PAUSED, UNPAUSE => RUNNING }[latest["action"]]
      rescue Integrations::RateLimited
        raise
      rescue ConvexApi::Error
        nil
      end

      def state_lines(api)
        events, _complete = audit_events(api, STATE_DAYS.days.ago)
        changes = events.select { |event| STATE_CHANGES.include?(event["action"]) }.reverse
        return "No pause, usage limit stop or state change in the last #{STATE_DAYS} days, so it is running as usual." if changes.empty?

        "State changes in the last #{STATE_DAYS} days, newest first. A paused or stopped deployment fails every function call:\n" \
          "#{changes.map { |event| event_line(event) }.join("\n")}"
      rescue Integrations::RateLimited
        raise
      rescue ConvexApi::Error => error
        Sentence.join("Its audit log could not be read, so whether it was paused is not known", error)
      end

      # Every audit log event since from, least recent first as Convex returns them, and whether all were read.
      def audit_events(api, from)
        from_ms = (from.to_f * 1000).to_i
        events = []
        cursor = nil
        AUDIT_PAGES.times do
          page = api.audit_log(from: from_ms, cursor: cursor)
          events.concat(Array(page["items"]))
          cursor = page.dig("pagination", "nextCursor")
          return [ events, true ] unless page.dig("pagination", "hasMore") && cursor.present?
        end
        [ events, false ]
      end

      # One audit log event, with what Convex recorded about it as it wrote it, since its shape is not published.
      def event_line(event)
        at = Capabilities::Answers.time_of(event["createTime"])&.iso8601 || "unknown time"
        metadata = event["metadata"].presence && event["metadata"].to_json.truncate(METADATA_LIMIT)
        [ at, event["action"], "by #{actor(event['actor'])}", (metadata && "details #{metadata}") ].compact.join(", ")
      end

      def actor(actor)
        actor = actor.to_h
        case actor["kind"]
        when ACTOR_MEMBER then "a member in the dashboard (member #{actor['member_id']})"
        when ACTOR_TOKEN then "a deploy key or token (token #{actor['token_id']}#{", member #{actor['member_id']}" if actor['member_id']})"
        when ACTOR_SYSTEM then "Convex itself"
        else "someone Convex did not name"
        end
      end

      # The executions from the start of the range to its end. The endpoint answers what the deployment still keeps after
      # the cursor.
      def executions(environment_row, started, ended)
        entries = Array(api(environment_row).function_logs(cursor: (started.to_f * 1000).to_i)["entries"])
        entries.select { |entry| (at = executed_at(entry)).nil? || at <= ended }
      end

      def of_function(executions, function)
        return executions if function.blank?

        executions.select { |execution| execution["identifier"].to_s.downcase.include?(function.to_s.downcase) }
      end

      def failed?(execution) = execution["kind"] == COMPLETION && execution["error"].present?

      def executed_at(execution) = Capabilities::Answers.time_of(execution["timestamp"])

      # What one execution printed, a line each, and its error when it failed. A line is a plain string or a structured
      # line with its own level, messages and time in milliseconds.
      def lines_of(execution)
        source = "#{execution['udfType']} #{execution['identifier']}".strip
        fallback = executed_at(execution)
        lines = Array(execution["logLines"]).filter_map do |line|
          if line.is_a?(Hash)
            at = Capabilities::Answers.time_of(line["timestamp"]) || fallback
            text = "#{line['level']} #{Array(line['messages']).join(' ')}#{' (truncated)' if line['isTruncated']}"
          else
            at = fallback
            text = line.to_s
          end
          Telemetry::LogLine.new(at: at, source: source, text: text) if at
        end
        lines << Telemetry::LogLine.new(at: fallback, source: source, text: "#{LEVEL_ERROR} failed: #{execution['error']}") if failed?(execution) && fallback
        lines
      end

      def kept?(text, arguments)
        lowered = text.to_s.downcase
        return false if arguments["text"].present? && !lowered.include?(arguments["text"].to_s.downcase)
        return false if arguments["exclude"].present? && lowered.include?(arguments["exclude"].to_s.downcase)

        true
      end

      # The deployment keeps a recent window of executions, so a range that starts before the oldest one returned may be
      # missing lines.
      def window_note(executions, started)
        oldest = executions.filter_map { |execution| executed_at(execution) }.min
        return nil unless oldest.nil? || oldest > started + 1.minute

        reach = oldest ? "The oldest execution it still keeps is from #{oldest.utc.iso8601}." : "It returned no executions for this range."
        "#{reach} A Convex deployment keeps only its recent function logs, so older ones are only in a log stream the team " \
          "set up, such as Datadog, if it has one."
      end
    end
  end
end
