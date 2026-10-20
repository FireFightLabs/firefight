module Integrations
  module Packs
    # What Firefight reads for a Turso connection that its hosted MCP server cannot: a database's usage, rows read and
    # written, storage and bytes synced, through the Platform API (GET .../databases/{name}/usage). The server's sign-in is
    # issued by api.turso.tech and scoped to an organization or one of its groups (docs.turso.tech/integrations/mcp), so the
    # connection's own token is sent, and a token the Platform API does not take is told how to connect with one it does.
    # The organization is the one the token reaches that holds the database, read from the API, never guessed. Every call
    # is TursoApi's.
    class Turso < NativePack
      DATABASE = "database".freeze
      FROM = "from".freeze
      TO = "to".freeze
      # A token reaching more organizations than this is asked to name the database's own another way.
      ORGANIZATIONS_TRIED = 5
      NEEDS_TOKEN = "Turso's Platform API did not take this connection's token, so its usage cannot be read. Connect Turso again " \
                    "and choose Use a token instead, with an API token scoped to the organization, made with turso auth api-tokens mint and its --org flag.".freeze
      FIELDS = { "rows_read" => "rows read", "rows_written" => "rows written", "storage_bytes" => "storage", "bytes_synced" => "synced" }.freeze

      def self.beside_server? = true

      tool :database_usage,
           summary: "Shows a Turso database's rows read and written, storage and bytes synced over a period.",
           description: "A Turso database's usage over a period from Turso's Platform API: rows read, rows written, storage and bytes " \
                        "synced, in all and for each of its instances. Without from and to it is the current calendar month, which is " \
                        "what Turso bills and limits by",
           params_schema: {
             "type" => "object",
             "properties" => {
               DATABASE => { "type" => "string", "description" => "The database's name" },
               FROM => { "type" => "string", "description" => "Start of the period, ISO 8601 such as 2026-10-01T00:00:00Z (optional, this month)" },
               TO => { "type" => "string", "description" => "End of the period, ISO 8601 (optional, this month)" }
             },
             "required" => [ DATABASE ]
           },
           read_only: true

      def database_usage(environment_row:, arguments:)
        database = arguments[DATABASE].to_s.strip
        fail! "Say which database, by its name." if database.empty?

        from, to = [ FROM, TO ].map { |key| time(arguments[key], key) }
        api = TursoApi.new(Credentials.headers_for(environment_row)["Authorization"].to_s)
        organization, usage = read { found(api, database, from, to) }
        period = from || to ? "from #{from || 'the start of this month'} to #{to || 'now'}" : "this calendar month"
        lines = [ "#{database} in #{organization['name'] || organization['slug']}, #{period}: #{figures(usage['total'])}." ]
        instances = Array(usage["instances"]).select { |each| each.is_a?(Hash) }
        lines += instances.map { |instance| "  instance #{instance['uuid']}: #{figures(instance['usage'])}" } if instances.size > 1
        lines.join("\n")
      end

      private

      # The organization holding the database and its usage. A token reaching one organization asks that one, and one
      # reaching several asks each until one has the database.
      def found(api, database, from, to)
        organizations = api.organizations
        fail! "This connection's token reaches no Turso organization." if organizations.empty?
        if organizations.size > ORGANIZATIONS_TRIED
          fail! "This connection's token reaches #{organizations.size} organizations, more than Firefight asks in turn. Connect Turso with a token scoped to the database's organization."
        end

        organizations.each do |organization|
          return [ organization, api.usage(organization["slug"], database, from: from, to: to) ]
        rescue TursoApi::NotFound
          next
        end
        fail! "No Turso organization this connection reaches has a database named #{database}."
      end

      def read
        yield
      rescue TursoApi::Refused
        fail! NEEDS_TOKEN
      rescue TursoApi::Error => error
        fail! error.message
      end

      def time(value, key)
        return if value.blank?

        Time.iso8601(value.to_s.strip).utc.iso8601
      rescue ArgumentError
        fail! "#{key} is an ISO 8601 time with Z or an offset, such as 2026-10-01T00:00:00Z."
      end

      def figures(usage)
        usage = usage.to_h
        FIELDS.filter_map do |field, words|
          value = usage[field]
          next if value.nil?

          shown = field.include?("bytes") ? ActiveSupport::NumberHelper.number_to_human_size(value) : ActiveSupport::NumberHelper.number_to_delimited(value)
          "#{shown} #{words}"
        end.join(", ").presence || "no usage given"
      end
    end
  end
end
