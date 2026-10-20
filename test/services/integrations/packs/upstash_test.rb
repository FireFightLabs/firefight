require "test_helper"

module Integrations
  module Packs
    class UpstashTest < ActiveSupport::TestCase
      KEY = "Bearer ops@example.com:key-123".freeze
      BACKUPS = [ { "backup_id" => "bk-1", "name" => "before-migration", "state" => "completed", "creation_time" => 1_760_000_000 },
                  { "backup_id" => "bk-2", "name" => "nightly", "state" => "pending" } ].freeze

      setup do
        @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "upstash", name: "Upstash",
                                                                             settings: { "server_url" => "https://mcp.upstash.com/mcp" })
        @row = @integration.integration_environments.create!
        @pack = Upstash.new(@integration)
      end

      test "a restore checks the backup is the database's own and complete, then restores it with the key as Basic" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        UpstashApi.expects(:new).with("ops@example.com", "key-123").returns(api = mock("api"))
        api.expects(:backups).with("db-1").returns(BACKUPS)
        api.expects(:restore_backup).with("db-1", "bk-1").returns({})

        text = restore("database_id" => "db-1", "backup_id" => "bk-1")
        assert_equal "Upstash restored db-1 from backup before-migration, taken 2025-10-09T08:53:20Z. What the database held since then was " \
                     "replaced by the backup.", text
      end

      test "a backup that is another's or not complete is refused before anything is restored" do
        Credentials.stubs(:headers_for).returns("Authorization" => KEY)
        UpstashApi.any_instance.stubs(:backups).returns(BACKUPS)
        UpstashApi.any_instance.expects(:restore_backup).never

        assert_match "db-1 has no backup bk-9. Its backups are bk-1 (before-migration, completed), bk-2 (nightly, pending).",
                     refusal("database_id" => "db-1", "backup_id" => "bk-9")
        assert_match "Backup bk-2 is pending", refusal("database_id" => "db-1", "backup_id" => "bk-2")
      end

      test "a connection signed in rather than made with a Developer API key is told how to connect again" do
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer oauth-token")
        UpstashApi.expects(:new).never

        assert_match "Connect Upstash again and choose Use a token instead, with the account's Email and a Developer API key", refusal("database_id" => "db-1", "backup_id" => "bk-1")
      end

      private

      def restore(arguments) = @pack.call("restore_redis_backup", environment_row: @row, arguments: arguments)

      def refusal(arguments) = assert_raises(Integrations::Error) { restore(arguments) }.message
    end
  end
end
