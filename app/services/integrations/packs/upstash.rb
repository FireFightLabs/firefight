module Integrations
  module Packs
    # What Firefight does for an Upstash connection that its hosted MCP server cannot: restoring a Redis database from one
    # of its backups, through the Developer API (POST /redis/restore-backup/{id}). Upstash's server also takes a Developer
    # API key, as Authorization: Bearer email:API_KEY (upstash.com/docs/agent-resources/mcp), so a connection made with one
    # reaches both, the key sent to the Developer API as Basic as it asks. A connection signed in with OAuth holds a token
    # only for the server, so it is told to connect again with a key. Every call is UpstashApi's.
    class Upstash < NativePack
      DATABASE = "database_id".freeze
      BACKUP = "backup_id".freeze
      # A Developer API key as Upstash's server takes it, the account's email and the key after a colon.
      KEY = /\ABearer\s+(?<email>[^\s:]+@[^\s:]+):(?<key>\S+)\z/
      COMPLETED = "completed".freeze
      NEEDS_KEY = "Restoring a backup goes through Upstash's Developer API, which takes a Developer API key and not the sign-in this " \
                  "connection was made with. Connect Upstash again and choose Use a token instead, with the account's Email and a Developer API " \
                  "key from the Upstash console's Account, API Keys.".freeze

      def self.beside_server? = true

      tool :restore_redis_backup,
           summary: "Restores an Upstash Redis database from one of its backups, replacing its data.",
           description: "Put an Upstash Redis database's data back to one of its backups, by the backup's id as redis_list_backups gives " \
                        "it. Everything written since the backup is replaced by what the backup holds, so take a backup of the database " \
                        "as it is now first if anything since may be needed. It checks the backup is the database's own and complete " \
                        "first. Needs a connection made with a Developer API key",
           params_schema: {
             "type" => "object",
             "properties" => {
               DATABASE => { "type" => "string", "description" => "The database's id, as redis_list_databases gives it" },
               BACKUP => { "type" => "string", "description" => "The backup's id, as redis_list_backups gives it" }
             },
             "required" => [ DATABASE, BACKUP ]
           },
           read_only: false

      def restore_redis_backup(environment_row:, arguments:)
        database, backup_id = arguments.values_at(DATABASE, BACKUP).map { |value| value.to_s.strip }
        fail! "Say which database and which of its backups, by their ids." if database.empty? || backup_id.empty?

        api = api(environment_row)
        backups = read { api.backups(database) }
        backup = backups.find { |each| each.is_a?(Hash) && each["backup_id"].to_s == backup_id }
        fail! "#{database} has no backup #{backup_id}. Its backups are #{listed(backups)}." unless backup
        fail! "Backup #{backup_id} is #{backup['state']}, so it cannot be restored until it completes." unless backup["state"] == COMPLETED

        read { api.restore_backup(database, backup_id) }
        "Upstash restored #{database} from backup #{backup['name'].presence || backup_id}, taken #{taken(backup)}. What the database held " \
          "since then was replaced by the backup."
      end

      private

      def api(environment_row)
        found = Credentials.headers_for(environment_row)["Authorization"].to_s.match(KEY)
        fail! NEEDS_KEY unless found

        UpstashApi.new(found[:email], found[:key])
      end

      def read
        yield
      rescue UpstashApi::Refused => error
        fail! "#{error.message}. The Developer API key has to belong to the account or team that holds the database."
      rescue UpstashApi::Error => error
        fail! error.message
      end

      def taken(backup)
        at = Capabilities::Answers.time_of(backup["creation_time"])
        at ? at.utc.iso8601 : "at a time Upstash did not say"
      end

      def listed(backups)
        names = backups.select { |each| each.is_a?(Hash) }.first(10).map { |each| "#{each['backup_id']} (#{each['name']}, #{each['state']})" }
        names.any? ? names.join(", ") : "none"
      end
    end
  end
end
