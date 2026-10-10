require "test_helper"

module Integrations
  module Packs
    # Trigger.dev's general read, api_read, and its guard.
    class TriggerDevReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "trigger_dev", name: "Trigger.dev")
        @row = @integration.integration_environments.create!
        TriggerDev.store_credentials!(@row, TriggerDev::API_KEY => "tr_prod_sk_key")
        @row.store_fields!(TriggerDev::PROJECT => "proj_abc")
        @pack = TriggerDev.new(@integration)
      end

      test "api_read only reads, and a run read by its id links the run's page" do
        assert TriggerDev.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        assert_equal ReadGuards::TriggerDev, Provider.for("trigger_dev").read_guard
        TriggerDevApi.any_instance.expects(:read).with("/api/v1/runs/run_abc123/result", {}).returns("ok" => false, "error" => { "message" => "boom" })

        shown = text(call("path" => "/api/v1/runs/run_abc123/result"))

        assert_match "Trigger.dev answered GET /api/v1/runs/run_abc123/result.", shown
        assert_match "boom", shown
        assert_match "/projects/v3/proj_abc/runs/run_abc123", shown
      end

      test "environment variables come back as their names, and a path outside /api is said as a failure the agent can fix" do
        assert ReadGuards::TriggerDev.secret?("/api/v1/projects/proj_abc/envvars/prod")
        TriggerDevApi.any_instance.stubs(:read).returns([ { "name" => "DATABASE_URL", "value" => "postgres://u:p@h/db", "isSecret" => false } ])

        shown = text(call("path" => "/api/v1/projects/proj_abc/envvars/prod"))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "u:p@h"
        assert_raises(NativePack::Error) { call("path" => "/v1/runs") }
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
