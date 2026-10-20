module Integrations
  module Packs
    # What Firefight does for a ClickHouse Cloud connection that its remote MCP server, whose every tool reads, cannot,
    # through the Cloud API with the connection's own API key: scaling a service (instanceReplicaScalingUpdate, PATCH
    # .../services/{id}/replicaScaling), starting, waking or stopping it (instanceStateUpdate, PATCH .../state) and reading
    # the organization's activity log (activityGetList and activityGet). ClickHouse's server takes an API key as HTTP Basic
    # too, so a connection made with one reaches both. A connection signed in with OAuth holds a token only for the
    # server, so it is told to connect again with a key. Every limit, field and permission is the API's own, from its
    # OpenAPI description. Every call is ClickhouseApi's.
    class Clickhouse < NativePack
      ORGANIZATION = Capabilities::Clickhouse::ORGANIZATION
      SERVICE = Capabilities::Clickhouse::SERVICE
      REPLICAS = "numReplicas".freeze
      MIN_MEMORY = "minReplicaMemoryGb".freeze
      MAX_MEMORY = "maxReplicaMemoryGb".freeze
      IDLE = "idleScaling".freeze
      IDLE_TIMEOUT = "idleTimeoutMinutes".freeze
      MEMORY_LEAST = 8
      MEMORY_MOST = 356
      MEMORY_STEP = 4
      REPLICAS_LEAST = 1
      REPLICAS_MOST = 50
      IDLE_TIMEOUT_LEAST = 5
      HORIZONTAL = "horizontal".freeze
      BASIC = /\ABasic\s+\S+/
      # The API key permission each call requires, as the API's description names it.
      SCALING_PERMISSION = "control-plane:service:manage-scaling-config".freeze
      STATE_PERMISSION = "control-plane:service:manage".freeze
      VIEW_PERMISSION = "control-plane:service:view".freeze
      ACTIVITIES_PERMISSION = "control-plane:organization:view-activities".freeze
      # ServiceStatePatchRequest's commands. awake wakes an idle service and does not start a stopped one.
      START = "start".freeze
      STOP = "stop".freeze
      AWAKE = "awake".freeze
      # Service states (the Service schema's state) from which each command makes sense.
      STARTABLE = %w[stopped].freeze
      WAKEABLE = %w[idle].freeze
      STOPPABLE = %w[running idle partially_running degraded].freeze
      ACTIVITY = "activityId".freeze
      FROM = "from".freeze
      TO = "to".freeze
      ACTIVITY_DAYS = 30
      ACTIVITY_LIMIT = 50
      ACTIVITY_MOST = 500
      # Activities that begin something a later one ends, so the two are one run with how long it took: maintenance, and
      # a service starting or waking until it runs.
      RUNNING_NOW = %w[service_running service_partially_running].freeze
      PAIRS = {
        "service_maintenance_start" => %w[service_maintenance_end], "service_start" => RUNNING_NOW, "service_awaken" => RUNNING_NOW
      }.freeze
      SERVICE_PREFIX = "service_".freeze
      FAILED_WORD = "failed".freeze

      def self.beside_server? = true

      tool :scale_service,
           summary: "Sets a ClickHouse Cloud service's replicas, memory per replica or idle scaling.",
           description: "Change how a ClickHouse Cloud service scales: its number of replicas, the memory each replica scales between " \
                        "in GiB (a multiple of #{MEMORY_STEP} from #{MEMORY_LEAST} to #{MEMORY_MOST}, the same for both to fix it), and " \
                        "whether it scales to zero when idle and after how many minutes. Give only what changes. It answers what the " \
                        "service ran with before and what it runs with now. Needs a connection made with an API key",
           params_schema: {
             "type" => "object",
             "properties" => {
               ORGANIZATION => { "type" => "string", "description" => "The organization's id, as get_organizations gives it" },
               SERVICE => { "type" => "string", "description" => "The service's id, as get_services_list gives it" },
               REPLICAS => { "type" => "integer", "description" => "How many replicas to run, #{REPLICAS_LEAST} to #{REPLICAS_MOST} (optional)" },
               MIN_MEMORY => { "type" => "number", "description" => "The least memory per replica in GiB (optional)" },
               MAX_MEMORY => { "type" => "number", "description" => "The most memory per replica in GiB (optional)" },
               IDLE => { "type" => "boolean", "description" => "Whether the service scales to zero when idle (optional)" },
               IDLE_TIMEOUT => { "type" => "integer", "description" => "Minutes idle before it scales to zero, #{IDLE_TIMEOUT_LEAST} or more (optional)" }
             },
             "required" => [ ORGANIZATION, SERVICE ]
           },
           read_only: false

      ON_SERVICE = {
        "type" => "object",
        "properties" => {
          ORGANIZATION => { "type" => "string", "description" => "The organization's id, as get_organizations gives it" },
          SERVICE => { "type" => "string", "description" => "The service's id, as get_services_list gives it" }
        },
        "required" => [ ORGANIZATION, SERVICE ]
      }.freeze

      tool :start_service,
           summary: "Starts a stopped ClickHouse Cloud service, or wakes an idle one.",
           description: "Start a ClickHouse Cloud service that was stopped, or wake one that idled. It reads the service first and " \
                        "refuses one already running or on its way. Needs a connection made with an API key",
           params_schema: ON_SERVICE,
           read_only: false

      tool :stop_service,
           summary: "Stops a ClickHouse Cloud service, so nothing can query it until it is started.",
           description: "Stop a ClickHouse Cloud service. Every query to it fails until it is started again, so it is for a service " \
                        "that runs up cost or harm while nobody should use it. It reads the service first and refuses one already " \
                        "stopped or on its way. Needs a connection made with an API key",
           params_schema: ON_SERVICE,
           read_only: false

      tool :activities,
           summary: "Lists what changed in a ClickHouse Cloud organization or service, and who did it.",
           description: "The organization's activity log, newest first: each activity with when, what it was (a service started, " \
                        "stopped, scaled, upgraded or put in maintenance, a key or member added, and the rest) and who or what did " \
                        "it. With #{SERVICE}, only that service's, read as runs, a start or maintenance with how long it took. With " \
                        "#{ACTIVITY}, that one activity. Needs a connection made with an API key",
           params_schema: {
             "type" => "object",
             "properties" => {
               ORGANIZATION => { "type" => "string", "description" => "The organization's id, as get_organizations gives it" },
               SERVICE => { "type" => "string", "description" => "Only this service's activities, by its id (optional)" },
               ACTIVITY => { "type" => "string", "description" => "One activity, by its id (optional)" },
               FROM => { "type" => "string", "description" => "From this time, ISO 8601 (optional, #{ACTIVITY_DAYS} days ago)" },
               TO => { "type" => "string", "description" => "Until this time, ISO 8601 (optional, now)" },
               "name" => { "type" => "string", "description" => "Only activities whose kind contains this, such as maintenance (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{ACTIVITY_LIMIT})" }
             },
             "required" => [ ORGANIZATION ]
           },
           read_only: true

      def scale_service(environment_row:, arguments:)
        organization, service_id = service_of(arguments)
        body = scaling(arguments)
        fail! "Say what to change: #{REPLICAS}, #{MIN_MEMORY} and #{MAX_MEMORY}, #{IDLE} or #{IDLE_TIMEOUT}." if body.empty?

        api = api(environment_row, "scale a service", SCALING_PERMISSION)
        before = read(SCALING_PERMISSION) { api.service(organization, service_id) }
        if body.key?(REPLICAS) && before["autoscalingMode"] == HORIZONTAL
          fail! "#{before['name']} scales its replica count itself, between #{before['minReplicas']} and #{before['maxReplicas']}, so its " \
                "replicas cannot be fixed here. Change its memory or idle scaling, or its autoscaling in the ClickHouse Cloud console."
        end
        after = read(SCALING_PERMISSION) { api.replica_scaling(organization, service_id, body) }
        "ClickHouse Cloud changed how #{before['name'] || service_id} scales.\nBefore: #{shape(before)}.\nNow: #{shape(after)}."
      end

      # A stopped service is started, and an idle one woken, which the API keeps apart: awake does not start a stopped one.
      def start_service(environment_row:, arguments:)
        organization, service_id = service_of(arguments)
        api = api(environment_row, "start a service", STATE_PERMISSION)
        before = read(STATE_PERMISSION) { api.service(organization, service_id) }
        name = before["name"] || service_id
        command = if STARTABLE.include?(before["state"]) then START
        elsif WAKEABLE.include?(before["state"]) then AWAKE
        end
        fail! "#{name} is #{before['state'] || 'in a state ClickHouse did not say'}, so there is nothing to start." unless command

        after = read(STATE_PERMISSION) { api.state(organization, service_id, command) }
        verb = command == AWAKE ? "is waking" : "is starting"
        "ClickHouse Cloud #{verb} #{name}, which was #{before['state']}. It is #{after['state'] || 'on its way'} now and takes queries once it is running."
      end

      def stop_service(environment_row:, arguments:)
        organization, service_id = service_of(arguments)
        api = api(environment_row, "stop a service", STATE_PERMISSION)
        before = read(STATE_PERMISSION) { api.service(organization, service_id) }
        name = before["name"] || service_id
        fail! "#{name} is #{before['state'] || 'in a state ClickHouse did not say'}, so there is nothing to stop." unless STOPPABLE.include?(before["state"])

        after = read(STATE_PERMISSION) { api.state(organization, service_id, STOP) }
        "ClickHouse Cloud is stopping #{name}, which was #{before['state']}. It is #{after['state'] || 'on its way'} now, and every query to it " \
          "fails until start_service starts it again."
      end

      # The organization's activities, or one service's as runs, which a watch and what changed read as its history.
      def activities(environment_row:, arguments:)
        organization = arguments[ORGANIZATION].to_s.strip
        fail! "Say which organization, by its id." if organization.empty?

        api = api(environment_row, "read the activity log", ACTIVITIES_PERMISSION)
        service_id = arguments[SERVICE].to_s.strip.presence
        one = arguments[ACTIVITY].to_s.strip.presence
        listed = if one
          [ read(ACTIVITIES_PERMISSION) { api.activity(organization, one) } ]
        else
          from, to = window(arguments)
          read(ACTIVITIES_PERMISSION) { api.activities(organization, from: from, to: to) }
        end
        listed = listed.select { |activity| activity.is_a?(Hash) && activity["id"].present? }
        listed = listed.select { |activity| activity["serviceId"] == service_id } if service_id
        limit = Capabilities::Answers.limit(arguments, ACTIVITY_MOST, default: ACTIVITY_LIMIT)
        return activity_runs(listed, service_id ? "service #{service_id}" : "the organization", arguments, limit, paired: one.nil?) if service_id || one

        listed = listed.select { |activity| activity["type"].to_s.include?(arguments["name"].to_s) } if arguments["name"].present?
        return "ClickHouse Cloud records no activity in this organization in that time." if listed.empty?

        lines = listed.sort_by { |activity| activity["createdAt"].to_s }.reverse.first(limit).map { |activity| activity_line(activity) }
        "The organization's latest #{lines.size} activities, newest first.\n#{lines.join("\n")}"
      end

      private

      def service_of(arguments)
        organization, service_id = arguments.values_at(ORGANIZATION, SERVICE).map { |value| value.to_s.strip }
        fail! "Say which service, by its organization's id and its own." if organization.empty? || service_id.empty?

        [ organization, service_id ]
      end

      def api(environment_row, what, permission)
        authorization = Credentials.headers_for(environment_row)["Authorization"].to_s
        unless authorization.match?(BASIC)
          fail! "To #{what}, Firefight goes through the ClickHouse Cloud API, which takes an API key and not the sign-in this connection " \
                "was made with. Connect ClickHouse again with an API key whose role holds #{permission}, pasted as Basic followed by " \
                "the key id and secret joined by a colon in base64."
        end

        ClickhouseApi.new(authorization)
      end

      def read(permission)
        yield
      rescue ClickhouseApi::Refused => error
        fail! "#{error.message}. The API key's role needs #{permission}#{" and #{VIEW_PERMISSION}" unless permission == ACTIVITIES_PERMISSION}."
      rescue ClickhouseApi::Error => error
        fail! error.message
      end

      # The range asked, or the last ACTIVITY_DAYS days, as ISO 8601.
      def window(arguments)
        from = arguments[FROM].to_s.strip.presence && Telemetry.parse_time(arguments[FROM])
        to = arguments[TO].to_s.strip.presence && Telemetry.parse_time(arguments[TO])
        fail! "#{FROM} and #{TO} are ISO 8601 times, such as 2026-10-20T14:30:00Z." if (arguments[FROM].present? && from.nil?) || (arguments[TO].present? && to.nil?)

        [ (from || ACTIVITY_DAYS.days.ago).utc.iso8601, to&.utc&.iso8601 ]
      end

      def activity_line(activity)
        [ activity["createdAt"], activity["type"].to_s.tr("_", " "), ("service #{activity['serviceId']}" if activity["serviceId"].present?),
          actor(activity) ].compact.join(", ")
      end

      def actor(activity)
        who = [ activity["actorType"], activity["actorDetails"].presence ].compact.join(" ")
        "by #{who}" if who.present?
      end

      # Each activity a run, ended when it happened, and a start, a wake or maintenance paired with what ended it, so it
      # says how long it took. One that has not ended yet is still running. A failed activity, such as a key check that
      # failed, failed.
      def activity_runs(listed, what, arguments, limit, paired:)
        ordered = listed.sort_by { |activity| activity["createdAt"].to_s }
        ended = Set.new
        runs = ordered.each_with_index.filter_map do |activity, index|
          next if ended.include?(activity["id"])

          type = activity["type"].to_s
          closing = PAIRS[type] && paired ? ordered[(index + 1)..].find { |later| PAIRS[type].include?(later["type"]) && !ended.include?(later["id"]) } : nil
          ended << closing["id"] if closing
          activity_run(activity, closing, open: PAIRS.key?(type) && paired && closing.nil?)
        end
        Capabilities::History.result(runs, what: what, name: arguments["name"], limit: limit)
      end

      def activity_run(activity, closing, open:)
        at = Telemetry.parse_time(activity["createdAt"])
        status = if open then Capabilities::History::RUNNING
        elsif activity["type"].to_s.include?(FAILED_WORD) then Capabilities::History::FAILED
        else Capabilities::History::SUCCEEDED
        end
        Capabilities::History::Run.new(
          id: activity["id"], name: activity["type"].to_s.delete_prefix(SERVICE_PREFIX), status: status, started_at: at,
          finished_at: (closing ? Telemetry.parse_time(closing["createdAt"]) : at unless open), detail: actor(activity)
        )
      end

      # Each value checked against the API's own limits before anything is sent.
      def scaling(arguments)
        body = {}
        if arguments[REPLICAS].present?
          replicas = Integer(arguments[REPLICAS].to_s, exception: false)
          fail! "#{REPLICAS} is a whole number from #{REPLICAS_LEAST} to #{REPLICAS_MOST}." unless replicas&.between?(REPLICAS_LEAST, REPLICAS_MOST)
          body[REPLICAS] = replicas
        end
        [ MIN_MEMORY, MAX_MEMORY ].each do |key|
          next if arguments[key].blank?

          memory = Float(arguments[key].to_s, exception: false)
          unless memory && memory == memory.to_i && memory.to_i.between?(MEMORY_LEAST, MEMORY_MOST) && (memory.to_i % MEMORY_STEP).zero?
            fail! "#{key} is GiB per replica, a multiple of #{MEMORY_STEP} from #{MEMORY_LEAST} to #{MEMORY_MOST}."
          end
          body[key] = memory.to_i
        end
        fail! "#{MIN_MEMORY} cannot be more than #{MAX_MEMORY}." if body.key?(MIN_MEMORY) && body.key?(MAX_MEMORY) && body[MIN_MEMORY] > body[MAX_MEMORY]
        body[IDLE] = ActiveModel::Type::Boolean.new.cast(arguments[IDLE]) unless arguments[IDLE].nil?
        if arguments[IDLE_TIMEOUT].present?
          minutes = Integer(arguments[IDLE_TIMEOUT].to_s, exception: false)
          fail! "#{IDLE_TIMEOUT} is a whole number of minutes, #{IDLE_TIMEOUT_LEAST} or more." unless minutes && minutes >= IDLE_TIMEOUT_LEAST
          body[IDLE_TIMEOUT] = minutes
        end
        body
      end

      # A service's scaling as the Service object gives it.
      def shape(service)
        service = service.to_h
        replicas = if service["autoscalingMode"] == HORIZONTAL then "#{service['minReplicas']} to #{service['maxReplicas']} replicas"
        elsif service[REPLICAS] then "#{service[REPLICAS]} #{'replica'.pluralize(service[REPLICAS].to_i)}"
        end
        memory = if service[MIN_MEMORY] && service[MIN_MEMORY] == service[MAX_MEMORY] then "#{service[MIN_MEMORY]} GiB each"
        elsif service[MIN_MEMORY] then "#{service[MIN_MEMORY]} to #{service[MAX_MEMORY]} GiB each"
        end
        idle = case service[IDLE]
        when true then "scales to zero after #{service[IDLE_TIMEOUT] || 'its default'} idle minutes"
        when false then "never idles"
        end
        [ replicas, memory, idle ].compact.join(", ").presence || "not said"
      end
    end
  end
end
