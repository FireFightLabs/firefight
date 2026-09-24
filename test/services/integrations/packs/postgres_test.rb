require "test_helper"

module Integrations
  module Packs
    class PostgresTest < ActiveSupport::TestCase
      ALLOWED = Postgres::Connection::ALLOWED_PRIVATE_HOSTS_ENV

      setup do
        @workspace = workspaces(:slack_workspace_one)
        @integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_NATIVE, provider: "postgresql", name: "Orders DB")
        @row = @integration.integration_environments.create!
        @previous = ENV[ALLOWED]
        ENV[ALLOWED] = "127.0.0.1"
        Postgres.store_connection_url!(@row, test_database_url)
        @pack = Postgres.new(@integration)
      end

      teardown do
        ENV[ALLOWED] = @previous
      end

      test "the tables are listed by schema, with their rough size" do
        assert_match(/^public \| incidents \| \d+ \| /, call(:list_tables))
      end

      test "a table is described with its columns, its keys and its indexes" do
        text = call(:describe_table, "table" => "incidents")

        assert_match "public.incidents", text
        assert_match "workspace_id | uuid | NO", text
        assert_match "PRIMARY KEY (id)", text
        assert_match "Indexes", text
      end

      test "a query returns its rows, and never more than the limit" do
        assert_match "1 rows.\none\n1", call(:run_query, "sql" => "SELECT 1 AS one;")
        assert_match "First #{Postgres::ROW_LIMIT} rows, there are more.", call(:run_query, "sql" => "SELECT generate_series(1, 500) AS n")
      end

      test "every query runs read only, with a time limit, whatever the user may do" do
        assert_match "on", call(:run_query, "sql" => "SELECT current_setting('transaction_read_only') AS read_only")
        assert_match "10s", call(:run_query, "sql" => "SELECT current_setting('statement_timeout') AS timeout")
      end

      test "a statement that would write is refused, however it is dressed" do
        [ "DELETE FROM incidents", "CREATE TABLE halon_was_here (id int)", "SELECT 1; DELETE FROM incidents" ].each do |sql|
          error = assert_raises(NativePack::Error) { call(:run_query, "sql" => sql) }
          assert_match(/Only a SELECT|Only reading is allowed|cannot insert multiple commands/, error.message)
        end

        error = assert_raises(NativePack::Error) do
          call(:run_query, "sql" => "WITH gone AS (DELETE FROM incidents RETURNING id) SELECT * FROM gone")
        end
        assert_match(/Only a SELECT|Only reading is allowed/, error.message)
        assert Incident.exists?
        error = assert_raises(NativePack::Error) { call(:explain_query, "sql" => "SELECT 1; DELETE FROM incidents") }
        assert_match "cannot insert multiple commands", error.message
      end

      test "a plan can be read, and run for real timings" do
        assert_match "Result", call(:explain_query, "sql" => "SELECT 1")
        assert_match "actual time", call(:explain_query, "sql" => "SELECT 1", "analyze" => true)
      end

      test "what the database is doing now says the connections, what runs longest and what is blocked" do
        text = call(:current_activity)

        assert_match "Connections by state", text
        assert_match "max_connections", text
        assert_match "Nothing is blocked.", text
      end

      test "table health reads the statistics Postgres keeps" do
        assert_match "dead_rows", call(:table_health)
      end

      test "a wrong password says it could not connect, and the health check fails on it" do
        Postgres.store_connection_url!(@row, test_database_url(password: "wrong"))

        error = assert_raises(NativePack::Error) { @pack.check_health!(@row) }
        assert_match "Could not connect to the database", error.message
        assert_no_match "wrong", error.message
      end

      test "an environment with no URL says to reconnect it" do
        @row.update_column(:credentials, nil)

        error = assert_raises(NativePack::Error) { call(:list_tables) }

        assert_match "Reconnect it", error.message
      end

      test "a private address is refused unless an operator allowed it" do
        ENV[ALLOWED] = ""

        assert_match "private network", Postgres.connection_url_refusal("postgresql://reader:secret@10.1.2.3:5432/app")
        assert_match "private network", Postgres.connection_url_refusal("postgresql://reader:secret@127.0.0.1/app")
        assert_match "private network", Postgres.connection_url_refusal("postgresql://reader:secret@100.64.0.9/app")

        ENV[ALLOWED] = "10.0.0.0/8"
        assert_nil Postgres.connection_url_refusal("postgresql://reader:secret@10.1.2.3:5432/app")
      end

      test "a URL that is not Postgres, has no host, a socket or several hosts is refused" do
        assert_match "must start with", Postgres.connection_url_refusal("mysql://reader:secret@db.example.com/app")
        assert_match "no host", Postgres.connection_url_refusal("postgresql:///app")
        assert_match "one host only", Postgres.connection_url_refusal("postgresql://reader:secret@db1.example.com,db2.example.com/app")
      end

      private

      def call(tool, arguments = {})
        @pack.call(tool.to_s, environment_row: @row, arguments: arguments)
      end

      def test_database_url(password: nil)
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        user = ERB::Util.url_encode(config[:username].to_s)
        secret = ERB::Util.url_encode((password || config[:password]).to_s)
        "postgresql://#{user}:#{secret}@127.0.0.1:#{config[:port] || 5432}/#{config[:database]}"
      end
    end
  end
end
