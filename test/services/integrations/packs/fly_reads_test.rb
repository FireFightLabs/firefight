require "test_helper"

module Integrations
  module Packs
    # Fly.io's general read, api_read, kept to the organization the connection names.
    class FlyReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly.io")
        @row = @integration.integration_environments.create!
        Fly.store_credentials!(@row, Fly::API_TOKEN => "FlyV1 fm2_x")
        @row.store_fields!(Fly::ORGANIZATION => "acme")
        @pack = Fly.new(@integration)
        FlyApi.any_instance.stubs(:app).with("web").returns("name" => "web", "organization" => { "slug" => "acme" })
        FlyApi.any_instance.stubs(:app).with("theirs").returns("name" => "theirs", "organization" => { "slug" => "other" })
        FlyApi.any_instance.stubs(:postgres_clusters).with("acme").returns([ { "id" => "pg1" } ])
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        assert Fly.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        assert_equal ReadGuards::Fly, Provider.for("fly").read_guard
      end

      test "a GET goes to the Machines API as its reference writes the path, linking the app's machines page" do
        Http.expects(:json).with do |uri, request, *|
          uri.to_s == "https://api.machines.dev/v1/apps/web/machines/m1/events?limit=5" && request["Authorization"] == "FlyV1 fm2_x"
        end.returns([ { "type" => "exit", "status" => "stopped" } ])

        shown = text(call("path" => "/v1/apps/web/machines/m1/events", "query" => { "limit" => 5 }))
        assert_match "Fly.io answered GET /v1/apps/web/machines/m1/events?limit=5.", shown
        assert_includes shown, "https://fly.io/apps/web/machines"
      end

      test "a list names the connection's organization, and another organization's app, org or cluster is refused" do
        FlyApi.any_instance.expects(:read).with("/v1/apps", { "org_slug" => "acme" }).returns("apps" => [])
        call("path" => "/v1/apps")

        FlyApi.any_instance.expects(:read).with("/v1/apps/theirs/machines", anything).never
        assert_match "reaches the one theirs is in", assert_raises(PolicyRefusal) { call("path" => "/v1/apps/theirs/machines") }.message
        assert_raises(PolicyRefusal) { call("path" => "/v1/apps", "query" => { "org_slug" => "other" }) }
        assert_raises(PolicyRefusal) { call("path" => "/v1/orgs/other/machines") }
        assert_raises(PolicyRefusal) { call("path" => "/v1/postgres/pg9/databases") }
      end

      test "a machine's environment and files never come back, and show_secrets is never sent" do
        FlyApi.any_instance.stubs(:read).with("/v1/apps/web/machines/m1", {}).returns(
          "id" => "m1", "config" => { "env" => { "DATABASE_URL" => "postgres://u:pw@h/db" }, "files" => [ { "guest_path" => "/etc/key", "raw_value" => "c2VjcmV0" } ] }
        )

        shown = text(call("path" => "/v1/apps/web/machines/m1"))
        assert_includes shown, "DATABASE_URL"
        %w[pw@h c2VjcmV0].each { |secret| assert_not_includes shown, secret }
        assert_raises(PolicyRefusal) { call("path" => "/v1/apps/web/secrets", "query" => { "show_secrets" => true }) }
      end

      test "a path outside the Machines API is said as a failure the agent can fix" do
        assert_match "start with /v1", assert_raises(NativePack::Error) { call("path" => "/apps/web") }.message
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
