module Integrations
  module Capabilities
    # Turso answers through its hosted MCP server at mcp.turso.ai. Turso names the server's tools in its agent skill,
    # tursodatabase/turso-mcp skills/turso/SKILL.md, and publishes their parameters only from the server. So each call
    # names the database with the parameter the connected tool reports, and refuses in words when it reports none
    # Firefight knows. The server offers no logs or metrics over time. Status reads the database through get_database,
    # and errors are its top queries through database_analytics, which the skill says covers a time range. Turso does not
    # publish how that tool takes a range, so the call leaves it to the tool's own and the answer says so when one was asked.
    # A rollback is Turso's point in time recovery, which never changes the database itself: create_branch makes a new
    # database from it as it was at a moment (the skill's "optionally from a point in time", the Platform API's seed
    # timestamp, docs.turso.tech/features/point-in-time-recovery), and the application is pointed at that one.
    module Turso
      extend Adapter

      PROVIDER = "Turso".freeze
      PROVIDER_KEY = "turso".freeze
      GET_DATABASE = "get_database".freeze
      DATABASE_ANALYTICS = "database_analytics".freeze
      CREATE_BRANCH = "create_branch".freeze
      KINDS = [ ResourceMap::KIND_DATABASE, ResourceMap::KIND_BRANCH ].freeze
      SUPPORTS = { STATUS => KINDS, ERRORS => KINDS, ROLLBACK => KINDS }.freeze
      TOOLS = { STATUS => GET_DATABASE, ERRORS => DATABASE_ANALYTICS, ROLLBACK => CREATE_BRANCH }.freeze
      # Their arguments are read off the connected tool, so they stay offered for when they cannot be.
      WRAPPED = [].freeze
      # The names the tool may give the database, in the order they are tried.
      DATABASE = %w[database_name databaseName database name db].freeze
      # The names create_branch may give the database it copies, the new one and the moment it copies, in the order tried.
      SOURCE = %w[source_database sourceDatabase source database_name databaseName database parent db].freeze
      BRANCH = %w[branch_name branchName new_database_name newDatabaseName new_name name].freeze
      POINT = %w[timestamp point_in_time pointInTime restore_point at].freeze
      RANGE_ARGS = %w[minutes start end].freeze
      # A Turso database's name takes lowercase letters, numbers and dashes, up to 64 (Platform API, Create Database).
      NAME_MOST = 64
      # The whole moment in UTC, so two restores of different moments never share a name. The same moment restored twice
      # names the copy that is already there, which Turso refuses, since an approved call must stay the same when retried.
      RESTORED_STAMP = "%Y%m%d%H%M%S".freeze

      OWN_PHRASES = { ERRORS => "read a database's top queries", ROLLBACK => "restore a database as it was at a moment, as a new database" }.freeze

      def self.phrase(key) = OWN_PHRASES.fetch(key) { super }

      def self.route(key, resource, given, tool: nil, settings: nil)
        return rollback(resource, given, tool) if key == ROLLBACK

        name = Answers.named(tool, DATABASE)
        tool_name = TOOLS.fetch(key)
        raise Unroutable, "Turso's #{tool_name} takes the database in a way Firefight does not know yet, so ask it with Turso's own tool." unless name

        arguments = { name => resource.name }
        note = key == ERRORS ? not_narrowed(resource, given) : nil
        return Route.new(tool_name: tool_name, arguments: arguments) unless note

        Route.new(tool_name: tool_name, arguments: arguments,
                  present: ->(result) { result.nil? || result["isError"] ? result : Answers.presented(result, "#{note}\n#{Answers.text(result)}") })
      end

      # The database as it was at to, an ISO 8601 time, made as a new database beside it, which is left as it is. The new
      # one is named after it and the moment asked, such as orders-restored-10201430.
      def self.rollback(resource, given, tool)
        # A time without Z or an offset would be read in the server's own zone, so it is refused rather than guessed.
        raise ArgumentError unless given["to"].to_s.strip.match?(/(Z|[+-]\d{2}:?\d{2})\z/i)

        at = Time.iso8601(given["to"].to_s.strip)
        raise Unroutable, "#{resource.name} can be restored only to a moment that has passed." if at > Time.current

        source = Answers.named(tool, SOURCE)
        branch = Answers.named(tool, BRANCH.reject { |each| each == source })
        point = Answers.named(tool, POINT)
        unless source && branch && point
          raise Unroutable, "Turso's #{CREATE_BRANCH} here takes the database, the new one's name or the moment in a way Firefight does not " \
                            "know yet, so restore it with Turso's own tool."
        end

        restored = restored_name(resource, at)
        Route.new(tool_name: CREATE_BRANCH, arguments: { source => resource.name, branch => restored, point => at.utc.iso8601 },
                  keeps: "#{resource.name} as it is now, untouched, beside the restored copy #{restored}",
                  present: lambda { |result|
                    next result if result.nil? || result["isError"]

                    Answers.presented(result, "Turso made #{restored} from #{resource.name} as it was at #{at.utc.iso8601}. #{resource.name} itself " \
                                              "is unchanged, so check the data in #{restored} and then point the application at it, by its own " \
                                              "hostname.\n#{Answers.text(result)}")
                  })
      rescue ArgumentError
        raise Unroutable, "Say when to restore #{resource.name} to, as an ISO 8601 time with Z or an offset, such as 2026-10-20T14:30:00Z, within Turso's point in time window."
      end

      # A copy of the same moment already on the map takes the next free number, such as shop-restored-20261020143000-2, so
      # a second restore of one moment makes a second copy. The name comes from the map, not a random value, so the call a
      # person approved is the call a retry sends, and a retry of a restore that already landed is refused by Turso as a
      # name taken rather than making a copy nobody asked for.
      def self.restored_name(resource, at)
        stamp = "-restored-#{at.utc.strftime(RESTORED_STAMP)}"
        base = resource.name.to_s.downcase.gsub(/[^a-z0-9-]/, "-").squeeze("-").delete_suffix("-")
        taken = ResourceMap::Resource.present.where(workspace_id: resource.workspace_id, provider: PROVIDER_KEY)
                                     .where("name LIKE ?", "%#{ResourceMap::Resource.sanitize_sql_like(stamp)}%").pluck(:name)
        (1..).lazy.map { |copy| copy == 1 ? stamp : "#{stamp}-#{copy}" }
             .map { |suffix| "#{base.first(NAME_MOST - suffix.length)}#{suffix}" }
             .find { |name| !taken.include?(name) }
      end

      # What the answer could not narrow to, said before it, since the tool takes no range, text or limit Firefight knows.
      def self.not_narrowed(resource, given)
        notes = []
        if RANGE_ARGS.any? { |each| given[each].present? }
          notes << "Turso does not publish how #{DATABASE_ANALYTICS} takes a time range, so these are #{resource.name}'s top queries over the tool's own default range, not the range asked."
        end
        notes << "#{DATABASE_ANALYTICS} takes no text to filter by, so these are all of its top queries, not only those containing #{given['text']}." if given["text"].present?
        notes << "#{DATABASE_ANALYTICS} takes no limit Firefight knows, so these are as many as it gives, which may be more than #{given['limit']}." if given["limit"].present?
        notes.join(" ").presence
      end

      private_class_method :not_narrowed, :rollback, :restored_name
    end
  end
end
