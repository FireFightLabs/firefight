require "test_helper"

module Integrations
  module Packs
    # Tinybird's general read, api_read, and its guard.
    class TinybirdReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "tinybird", name: "Tinybird")
        @row = @integration.integration_environments.create!
        Tinybird.store_credentials!(@row, Tinybird::TOKEN => "p.eyJ1IjoiYSJ9.sig")
        @pack = Tinybird.new(@integration)
        TinybirdApi.any_instance.stubs(:workspace).returns("id" => "w-1", "name" => "analytics")
      end

      test "api_read only reads, and a job is read by its id" do
        assert Tinybird.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        TinybirdApi.any_instance.expects(:read).with("/v0/jobs/j-1", {}).returns("id" => "j-1", "status" => "error", "error" => "Memory limit")

        shown = text(call("path" => "/v0/jobs/j-1"))

        assert_match "Tinybird answered GET /v0/jobs/j-1.", shown
        assert_match "Memory limit", shown
      end

      test "tokens come back as their names, and a path outside /v0 or /v1 is refused by Firefight's rule" do
        TinybirdApi.any_instance.stubs(:read).with("/v0/tokens", {}).returns("tokens" => [ { "name" => "admin token", "token" => "p.eyJ2IjoiYiJ9.other" } ])

        shown = text(call("path" => "/v0/tokens"))
        assert_includes shown, "admin token"
        assert_not_includes shown, "p.eyJ2IjoiYiJ9.other"
        assert_raises(PolicyRefusal) { call("path" => "/internal/x") }
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
