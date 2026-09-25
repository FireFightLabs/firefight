module Integrations
  module Packs
    # A Postgres database read straight from a connection URL, one per environment. Every call opens its own connection
    # in a read-only transaction with time limits (Postgres::Connection), so nothing here can change the database,
    # whatever the user in the URL may do.
    class Postgres < NativePack
      # The environment row's credential, which only this pack reads.
      CONNECTION_URL = "connection_url".freeze
      ROW_LIMIT = 200
      CELL_LIMIT = 300
      SQL_LIMIT = 10_000
      TABLE_LIMIT = 300
      ACTIVITY_LIMIT = 15
      QUERY_SHOWN = 400
      QUALIFIED_NAME = /\A(?:(?<schema>[A-Za-z_][\w$]*)\.)?(?<table>[A-Za-z_][\w$]*)\z/

      tool :list_tables,
           description: "List the tables in the database, by schema, with roughly how many rows each holds and its size on disk",
           params_schema: {
             "type" => "object",
             "properties" => { "schema" => { "type" => "string", "description" => "Only this schema, e.g. public (optional)" } }
           },
           read_only: true

      tool :describe_table,
           description: "The shape of one table: its columns with types, nulls and defaults, its primary key, indexes and foreign keys",
           params_schema: {
             "type" => "object",
             "properties" => { "table" => { "type" => "string", "description" => "The table, as schema.table or table for public, e.g. public.orders" } },
             "required" => [ "table" ]
           },
           read_only: true

      tool :run_query,
           description: "Run one read-only SELECT and get its rows back, at most #{ROW_LIMIT}. A query that would write is refused, " \
                        "and one running longer than #{Connection::STATEMENT_TIMEOUT_MS / 1000} seconds is stopped, so count or " \
                        "aggregate rather than reading a large table whole",
           params_schema: {
             "type" => "object",
             "properties" => { "sql" => { "type" => "string", "description" => "One SELECT, WITH or VALUES statement, no trailing semicolon needed" } },
             "required" => [ "sql" ]
           },
           read_only: true

      tool :explain_query,
           description: "The plan Postgres chooses for a query. With analyze it also runs the query and reports real timings and " \
                        "rows per step, which shows where a slow query spends its time",
           params_schema: {
             "type" => "object",
             "properties" => {
               "sql" => { "type" => "string", "description" => "The query to explain" },
               "analyze" => { "type" => "boolean", "description" => "Run it and report real timings (optional, off)" }
             },
             "required" => [ "sql" ]
           },
           read_only: true

      tool :current_activity,
           description: "What the database is doing now: connections by state against the limit, the longest running queries, " \
                        "and which sessions are blocked and by whom. Use it when something is slow, stuck or out of connections",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :table_health,
           description: "How tables are being read and kept: sequential against index scans, live and dead rows, and when each " \
                        "was last vacuumed and analyzed. Tables with the most dead rows first, or one table",
           params_schema: {
             "type" => "object",
             "properties" => { "table" => { "type" => "string", "description" => "One table, as schema.table (optional)" } }
           },
           read_only: true

      CERTIFICATES = "certificates".freeze

      def self.connection_refusal(url, certificates) = Connection.refusal(url, certificates)

      def self.certificate_fields = Connection::CERTIFICATES

      # Each connect sets the whole credential, so certificates left out are removed rather than kept from before.
      def self.store_connection!(environment_row, url:, certificates:)
        environment_row.store_credential!(CONNECTION_URL, url.to_s.strip)
        environment_row.store_credential!(CERTIFICATES, certificates.to_h.slice(*Connection::CERTIFICATES).compact_blank)
      end

      def list_tables(environment_row:, arguments:)
        schema = arguments["schema"].presence
        rows = read(environment_row) do |connection|
          connection.exec_params(<<~SQL, [ schema ]).to_a
            SELECT n.nspname AS schema, c.relname AS table,
                   GREATEST(c.reltuples, 0)::bigint AS rows_estimate,
                   pg_size_pretty(pg_total_relation_size(c.oid)) AS size
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
              AND n.nspname NOT LIKE 'pg_toast%' AND ($1::text IS NULL OR n.nspname = $1)
            ORDER BY n.nspname, c.relname
            LIMIT #{TABLE_LIMIT + 1}
          SQL
        end
        return "No tables#{" in #{schema}" if schema}." if rows.empty?

        "#{counted(rows.size, TABLE_LIMIT, 'tables')}\n#{grid(rows.first(TABLE_LIMIT))}"
      end

      def describe_table(environment_row:, arguments:)
        schema, table = qualified!(arguments["table"])
        read(environment_row) do |connection|
          columns = connection.exec_params(<<~SQL, [ schema, table ]).to_a
            SELECT column_name AS column, data_type AS type, is_nullable AS nullable, column_default AS default
            FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2 ORDER BY ordinal_position
          SQL
          fail! "#{schema}.#{table} does not exist or this user cannot see it." if columns.empty?

          indexes = connection.exec_params(<<~SQL, [ schema, table ]).to_a
            SELECT indexname AS index, indexdef AS definition FROM pg_indexes WHERE schemaname = $1 AND tablename = $2 ORDER BY indexname
          SQL
          keys = connection.exec_params(<<~SQL, [ "#{quote(schema)}.#{quote(table)}" ]).to_a
            SELECT conname AS constraint, pg_get_constraintdef(oid) AS definition
            FROM pg_constraint WHERE conrelid = $1::regclass AND contype IN ('p', 'f', 'u') ORDER BY contype, conname
          SQL
          [ "#{schema}.#{table}", grid(columns), ("Keys\n#{grid(keys)}" if keys.any?), ("Indexes\n#{grid(indexes)}" if indexes.any?) ].compact.join("\n\n")
        end
      end

      # A cursor takes only statements that return rows, and the fetch stops at the limit, so a huge table is never pulled
      # whole. The extended protocol takes exactly one statement, so nothing can ride after it.
      def run_query(environment_row:, arguments:)
        sql = statement!(arguments["sql"])
        read(environment_row) do |connection|
          connection.exec_params("DECLARE halon_query NO SCROLL CURSOR FOR #{sql}", [])
          result = connection.exec("FETCH #{ROW_LIMIT + 1} FROM halon_query")
          rows = result.to_a
          next "No rows." if rows.empty?

          "#{counted(rows.size, ROW_LIMIT, 'rows')}\n#{grid(rows.first(ROW_LIMIT), columns: result.fields)}"
        end
      rescue NativePack::Error => refused
        raise refused unless not_a_read?(refused.message, sql)

        fail! "Only a SELECT, WITH or VALUES statement can be run here."
      end

      def explain_query(environment_row:, arguments:)
        sql = statement!(arguments["sql"])
        options = arguments["analyze"] == true ? "ANALYZE, BUFFERS, " : ""
        read(environment_row) do |connection|
          connection.exec_params("EXPLAIN (#{options}FORMAT TEXT) #{sql}", []).map { |row| row["QUERY PLAN"] }.join("\n")
        end
      end

      def current_activity(environment_row:, arguments:)
        read(environment_row) do |connection|
          states = connection.exec(<<~SQL).to_a
            SELECT COALESCE(state, 'background') AS state, count(*) AS connections,
                   current_setting('max_connections') AS max_connections
            FROM pg_stat_activity GROUP BY 1 ORDER BY 2 DESC
          SQL
          longest = connection.exec(<<~SQL).to_a
            SELECT pid, usename AS user, state, wait_event_type AS waiting_on,
                   date_trunc('second', now() - query_start)::text AS running_for, left(query, #{QUERY_SHOWN}) AS query
            FROM pg_stat_activity
            WHERE state <> 'idle' AND pid <> pg_backend_pid() AND query_start IS NOT NULL
            ORDER BY query_start LIMIT #{ACTIVITY_LIMIT}
          SQL
          blocked = connection.exec(<<~SQL).to_a
            SELECT pid, pg_blocking_pids(pid)::text AS blocked_by,
                   date_trunc('second', now() - query_start)::text AS waiting_for, left(query, #{QUERY_SHOWN}) AS query
            FROM pg_stat_activity WHERE cardinality(pg_blocking_pids(pid)) > 0 LIMIT #{ACTIVITY_LIMIT}
          SQL
          [
            "Connections by state\n#{grid(states)}",
            longest.any? ? "Longest running\n#{grid(longest)}" : "Nothing is running but this check.",
            blocked.any? ? "Blocked\n#{grid(blocked)}" : "Nothing is blocked."
          ].join("\n\n")
        end
      end

      def table_health(environment_row:, arguments:)
        schema, table = qualified!(arguments["table"]) if arguments["table"].present?
        rows = read(environment_row) do |connection|
          connection.exec_params(<<~SQL, [ schema, table ]).to_a
            SELECT schemaname || '.' || relname AS table, seq_scan, idx_scan, n_live_tup AS live_rows, n_dead_tup AS dead_rows,
                   last_autovacuum::text AS last_autovacuum, last_vacuum::text AS last_vacuum,
                   last_autoanalyze::text AS last_autoanalyze
            FROM pg_stat_user_tables
            WHERE ($1::text IS NULL OR schemaname = $1) AND ($2::text IS NULL OR relname = $2)
            ORDER BY n_dead_tup DESC LIMIT 20
          SQL
        end
        rows.empty? ? "No statistics for #{table ? "#{schema}.#{table}" : 'any table'}." : grid(rows)
      end

      def check_health!(environment_row)
        read(environment_row) { |connection| connection.exec("SELECT 1") }
      end

      private

      def read(environment_row, &)
        credentials = environment_row.credentials_hash
        url = credentials[CONNECTION_URL]
        fail! "This environment has no connection URL. Reconnect it on the Integrations page." if url.blank?

        Connection.open(url, credentials[CERTIFICATES] || {}, &)
      end

      # How Postgres refuses a statement a cursor cannot hold, which is every statement that writes.
      def not_a_read?(message, sql)
        message.include?("syntax error at or near \"#{sql.split.first}\"") ||
          message.match?(/cannot open .* query as cursor|must not contain data-modifying statements/i)
      end

      def statement!(sql)
        sql = sql.to_s.strip.delete_suffix(";").strip
        fail! "Give the query to run." if sql.empty?
        fail! "The query is longer than #{SQL_LIMIT} characters." if sql.length > SQL_LIMIT
        sql
      end

      def qualified!(name)
        match = QUALIFIED_NAME.match(name.to_s.strip)
        fail! "Name the table as schema.table or table, e.g. public.orders." unless match

        [ match[:schema] || "public", match[:table] ]
      end

      def quote(identifier) = PG::Connection.quote_ident(identifier)

      def counted(size, limit, what) = size > limit ? "First #{limit} #{what}, there are more." : "#{size} #{what}."

      # Rows as the model reads them best, one line each, every cell cut short so one wide value cannot fill the window.
      def grid(rows, columns: rows.first&.keys || [])
        lines = rows.map { |row| columns.map { |column| cell(row[column]) }.join(" | ") }
        [ columns.join(" | "), *lines ].join("\n")
      end

      def cell(value)
        return "null" if value.nil?

        value.to_s.gsub(/\s+/, " ").truncate(CELL_LIMIT)
      end
    end
  end
end
