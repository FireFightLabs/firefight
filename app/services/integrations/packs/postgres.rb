module Integrations
  module Packs
    # A Postgres database read straight from a connection URL, one per environment. Every call opens its own connection
    # in a read-only transaction with time limits (Postgres::Connection), so no statement can write a table, whatever the
    # user in the URL may do. A read-only transaction still lets a function act on the server, such as ending another
    # session or writing over a second connection, so those are refused by name (ACTS).
    class Postgres < NativePack
      # The environment row's credential, which only this pack reads.
      CONNECTION_URL = "connection_url".freeze
      ROW_LIMIT = 200
      CELL_LIMIT = 300
      SQL_LIMIT = 10_000
      TABLE_LIMIT = 300
      ACTIVITY_LIMIT = 15
      QUERY_SHOWN = 400
      STATEMENT_LIMIT = 10
      STATEMENT_MOST = 50
      QUALIFIED_NAME = /\A(?:(?<schema>[A-Za-z_][\w$]*)\.)?(?<table>[A-Za-z_][\w$]*)\z/
      # Functions a read-only transaction allows that act on the server, which signal or end sessions, reload or rotate its
      # files, move the WAL or promote it, take advisory locks, reset its statistics, change a setting such as the
      # statement timeout, or reach another connection or a file. A quoted name counts, and so does an escaped one. So do
      # replication slots, notifications and the statement statistics, and any function that runs SQL handed to it as
      # text, since that text can spell a refused name in pieces this check never sees whole.
      ACTS = /\b(pg_terminate_backend|pg_cancel_backend|pg_reload_conf|pg_rotate_logfile|pg_switch_wal|pg_create_restore_point|pg_promote|
              pg_wal_replay_\w+|pg_log_backend_memory_contexts|pg_advisory\w*lock\w*|pg_stat_reset\w*|dblink\w*|lo_import|lo_export|lo_unlink|
              set_config|pg_read_file|pg_read_binary_file|pg_ls_dir|pg_\w*replication_slot\w*|pg_replication_origin_\w+|pg_notify|
              pg_logical_emit_message|pg_stat_statements_reset|pg_file_\w+|query_to_xml\w*|query_to_xmlschema|ts_stat)"?\s*\(/ix
      ESCAPED_NAME = /\bU&"/i
      # Catalogs that hold passwords, as role hashes or as the options of a connection to another server, which a query
      # never reads whatever the user in the URL may see.
      SECRET_CATALOGS = /\b(pg_authid|pg_shadow|pg_user_mappings?|user_mapping_options|pg_subscription|pg_stat_subscription|pg_foreign_server|
                         foreign_server_options)\b/ix
      # A statement setting a password, as the activity view shows it, possibly cut short before its closing quote.
      PASSWORD_SET = /(\bPASSWORD\s+)'[^']*(?:'|\z)/i

      tool :list_tables,
           summary: "Lists the database's tables with their row counts and size on disk.",
           description: "List the tables in the database, by schema, with roughly how many rows each holds and its size on disk",
           params_schema: {
             "type" => "object",
             "properties" => { "schema" => { "type" => "string", "description" => "Only this schema, e.g. public (optional)" } }
           },
           read_only: true

      tool :describe_table,
           summary: "Shows one table's columns, keys and indexes.",
           description: "The shape of one table: its columns with types, nulls and defaults, its primary key, indexes and foreign keys",
           params_schema: {
             "type" => "object",
             "properties" => { "table" => { "type" => "string", "description" => "The table, as schema.table or table for public, e.g. public.orders" } },
             "required" => [ "table" ]
           },
           read_only: true

      tool :run_query,
           summary: "Runs a read-only query and shows the rows it returns.",
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
           summary: "Shows how Postgres plans to run a query and where it spends its time.",
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
           summary: "Shows what the database is doing now, including slow and blocked queries.",
           description: "What the database is doing now: connections by state against the limit, the longest running queries, " \
                        "and which sessions are blocked and by whom. Use it when something is slow, stuck or out of connections",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :table_health,
           summary: "Shows how tables are scanned and vacuumed, and which hold the most dead rows.",
           description: "How tables are being read and kept: sequential against index scans, live and dead rows, and when each " \
                        "was last vacuumed and analyzed. Tables with the most dead rows first, or one table",
           params_schema: {
             "type" => "object",
             "properties" => { "table" => { "type" => "string", "description" => "One table, as schema.table (optional)" } }
           },
           read_only: true

      tool :database_status,
           summary: "Shows how the database stands now, from size and connections to replication.",
           description: "How the database stands now: its version, size, how long it has been up, connections against the " \
                        "limit, the oldest open transaction, its commits, rollbacks, deadlocks and cache hit rate since " \
                        "statistics were reset, how close it is to transaction ID wraparound, and its replication",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :database_errors,
           summary: "Shows rollbacks, deadlocks and conflicts, and the queries that take the most time.",
           description: "What has gone wrong in the database since its statistics were reset: rolled back transactions, " \
                        "deadlocks, queries cancelled by conflicts with recovery and temporary files, and, when pg_stat_statements " \
                        "is installed, the queries that took the most time in all, with how often each ran and its average time",
           params_schema: {
             "type" => "object",
             "properties" => {
               "text" => { "type" => "string", "description" => "Only queries containing this text, whatever the case (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many queries (optional, #{STATEMENT_LIMIT}, at most #{STATEMENT_MOST})" }
             }
           },
           read_only: true

      CERTIFICATES = "certificates".freeze
      PROVIDER = "postgresql".freeze
      # A database that answered the sweep is running.
      RUNNING = "running".freeze

      def self.connection_refusal(url, certificates) = Connection.refusal(url, certificates)

      def self.certificate_fields = Connection::CERTIFICATES

      def self.connection_url_words
        { placeholder: "postgresql://readonly:password@db.example.com:5432/app",
          hint: "Use a database user that can only read. Firefight also runs every query read-only and stops any that runs " \
                "longer than #{Connection::STATEMENT_TIMEOUT_MS / 1000} seconds. Connections over the internet are always encrypted." }
      end

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

        fail_policy! "Firefight only reads this database, so only a SELECT, WITH or VALUES statement runs here."
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

      # Every figure comes from statistics views any user who can connect may read, which are pg_stat_activity,
      # pg_stat_database, pg_stat_replication and pg_database, so it needs no extension and no extra role. A user without
      # pg_monitor sees only its own sessions' queries, and the replicas without their addresses.
      def database_status(environment_row:, arguments:)
        read(environment_row) do |connection|
          overview = connection.exec(<<~SQL).to_a
            SELECT current_database() AS database, current_setting('server_version') AS version,
                   pg_size_pretty(pg_database_size(current_database())) AS size,
                   date_trunc('second', now() - pg_postmaster_start_time())::text AS up_for,
                   CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END AS role,
                   (SELECT count(*) FROM pg_stat_activity) AS connections, current_setting('max_connections') AS max_connections,
                   (SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock') AS waiting_on_locks,
                   (SELECT date_trunc('second', max(now() - xact_start))::text FROM pg_stat_activity WHERE xact_start IS NOT NULL
                      AND pid <> pg_backend_pid()) AS oldest_transaction,
                   (SELECT age(datfrozenxid) FROM pg_database WHERE datname = current_database()) AS transaction_id_age
          SQL
          totals = connection.exec(<<~SQL).to_a
            SELECT xact_commit AS commits, xact_rollback AS rollbacks, deadlocks, conflicts, temp_files,
                   pg_size_pretty(temp_bytes) AS temp_written,
                   round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_percent, stats_reset::text AS since
            FROM pg_stat_database WHERE datname = current_database()
          SQL
          replicas = connection.exec(<<~SQL).to_a
            SELECT application_name AS replica, state, sync_state, replay_lag::text AS replay_lag FROM pg_stat_replication
          SQL
          behind = connection.exec(<<~SQL).getvalue(0, 0)
            SELECT CASE WHEN pg_is_in_recovery() THEN date_trunc('second', now() - pg_last_xact_replay_timestamp())::text END
          SQL
          [
            "Now\n#{grid(overview)}", "Since statistics were reset\n#{grid(totals)}",
            replicas.any? ? "Replicas\n#{grid(replicas)}" : "No replica streams from this database.",
            ("This is a replica, last replayed #{behind} ago." if behind)
          ].compact.join("\n\n")
        end
      end

      # The totals come from pg_stat_database, which any user who can connect may read, and the queries from
      # pg_stat_statements in whichever schema it was installed.
      def database_errors(environment_row:, arguments:)
        limit = arguments["limit"].to_i.positive? ? [ arguments["limit"].to_i, STATEMENT_MOST ].min : STATEMENT_LIMIT
        text = arguments["text"].to_s.strip.presence
        read(environment_row) do |connection|
          totals = connection.exec(<<~SQL).to_a
            SELECT xact_rollback AS rollbacks, deadlocks, conflicts, temp_files, pg_size_pretty(temp_bytes) AS temp_written,
                   xact_commit AS commits, stats_reset::text AS since
            FROM pg_stat_database WHERE datname = current_database()
          SQL
          [ "From pg_stat_database, since its statistics were last reset (since)\n#{grid(totals)}", statements(connection, text, limit) ].join("\n\n")
        end
      end

      # The one database the connection URL reaches, named by its host, port and name, which is all the map needs and
      # holds no credential.
      # The database is also reached at the host and port its URL names, which a service's DATABASE_URL may name too. A
      # service can reach it another way, such as through a pooler or a private host, which this address will not match.
      def map_of(environment_row)
        workspace = ConnectionSettings.of(environment_row).workspace
        found, endpoint = read(environment_row) do |connection|
          row = connection.exec(<<~SQL).to_a.first
            SELECT current_database() AS database, current_setting('server_version') AS version,
                   CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END AS role
          SQL
          database = ResourceMap::Found.new(
            provider: PROVIDER, account: connection.host, kind: ResourceMap::KIND_DATABASE,
            external_id: "#{connection.host}:#{connection.port}/#{row['database']}", name: row["database"], status: RUNNING,
            details: { "engine" => "PostgreSQL #{row['version']}", "type" => row["role"] }
          )
          [ database, ResourceMap::Endpoint.at(resource: database.key, host: connection.host, port: connection.port, workspace: workspace,
                                               database: row["database"]) ]
        end
        ResourceMap::Snapshot.new(resources: [ found ], endpoints: [ endpoint ])
      end

      def check_health!(environment_row)
        read(environment_row) { |connection| connection.exec("SELECT 1") }
      end

      private

      def read(environment_row, &)
        settings = ConnectionSettings.of(environment_row)
        url = settings.credential(CONNECTION_URL)
        fail! "This environment has no connection URL. Reconnect it on the Integrations page." if url.blank?

        Connection.open(url, settings.credential(CERTIFICATES) || {}, &)
      end

      # Read under a savepoint, so a server that has the extension but did not preload it says so instead of failing the
      # whole answer. Its time columns lost their exec_ prefix before Postgres 13, so the column is read from the view.
      # Its statistics reset apart from pg_stat_database's, so its own reset time (pg_stat_statements_info, Postgres 14
      # and later) heads its rows. Text is matched as written, its % and _ taken literally.
      def statements(connection, text, limit)
        schema = connection.exec("SELECT n.nspname FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace " \
                                 "WHERE e.extname = 'pg_stat_statements'").to_a.first&.fetch("nspname")
        return "pg_stat_statements is not installed in this database, so which queries cost the most is not known. Adding it is the person's call." unless schema

        view = "#{quote(schema)}.pg_stat_statements"
        current = connection.exec_params("SELECT 1 FROM pg_attribute WHERE attrelid = $1::regclass AND attname = 'total_exec_time'", [ view ]).ntuples.positive?
        prefix = current ? "exec_" : ""
        connection.exec("SAVEPOINT halon_statements")
        pattern = text&.gsub(/[\\%_]/) { |character| "\\#{character}" }
        rows = connection.exec_params(<<~SQL, [ pattern ]).to_a
          SELECT calls, round(total_#{prefix}time::numeric, 1) AS total_ms, round(mean_#{prefix}time::numeric, 1) AS mean_ms, rows,
                 left(query, #{QUERY_SHOWN}) AS query
          FROM #{view}
          WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
            AND ($1::text IS NULL OR query ILIKE '%' || $1 || '%')
          ORDER BY total_#{prefix}time DESC LIMIT #{limit}
        SQL
        hidden = statements_hidden?(connection)
        return "pg_stat_statements holds no queries#{" containing #{text}" if text} for this database.#{" #{HIDDEN_TEXT}" if hidden && text}" if rows.empty?

        heading = "Queries that took the most time in all, #{statements_since(connection, schema)}"
        unseen = rows.count { |row| row["query"] == INSUFFICIENT_PRIVILEGE }
        [ "#{heading}\n#{grid(rows)}", (HIDDEN_TEXT if unseen.positive?) ].compact.join("\n")
      rescue PG::ObjectNotInPrerequisiteState => error
        connection.exec("ROLLBACK TO SAVEPOINT halon_statements")
        "pg_stat_statements is installed but cannot be read: #{error.message.lines.first.to_s.strip.delete_prefix('ERROR:').strip}"
      end

      # Postgres shows another role's query text only to a role holding pg_read_all_stats, and this placeholder otherwise.
      INSUFFICIENT_PRIVILEGE = "<insufficient privilege>".freeze
      HIDDEN_TEXT = "Queries other roles ran show as #{INSUFFICIENT_PRIVILEGE}, and their text cannot be searched, since this connection's " \
                    "role does not hold pg_read_all_stats.".freeze

      def statements_hidden?(connection)
        connection.exec(<<~SQL).to_a.first["hidden"] == "t"
          SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pg_read_all_stats')
                      THEN NOT pg_has_role(current_user, 'pg_read_all_stats', 'member') ELSE false END AS hidden
        SQL
      end

      # When pg_stat_statements was last reset, from its own info view where the server has one.
      def statements_since(connection, schema)
        info = "#{quote(schema)}.pg_stat_statements_info"
        return "since pg_stat_statements was last reset" unless connection.exec_params("SELECT to_regclass($1) IS NOT NULL AS found", [ info ]).to_a.first["found"] == "t"

        reset = connection.exec("SELECT stats_reset::text AS reset FROM #{info}").to_a.first&.fetch("reset")
        reset ? "since pg_stat_statements was last reset at #{reset}" : "since pg_stat_statements was last reset"
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
        fail_policy! "Firefight only reads this database, and an escaped name could hide what a statement does." if sql.match?(ESCAPED_NAME)

        acting = sql[ACTS, 1]
        fail_policy! "Firefight only reads this database, and #{acting.downcase} acts on it." if acting
        holding = sql[SECRET_CATALOGS, 1]
        if holding
          fail_policy! "Firefight does not read #{holding.downcase}, since it holds passwords. Read pg_roles for roles and " \
                       "pg_stat_activity for sessions instead."
        end
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

        value.to_s.gsub(/\s+/, " ").gsub(PASSWORD_SET, "\\1'[hidden]'").truncate(CELL_LIMIT)
      end
    end
  end
end
