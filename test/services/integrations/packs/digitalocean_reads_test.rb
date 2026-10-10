require "test_helper"

module Integrations
  module Packs
    # DigitalOcean's general read, api_read.
    class DigitaloceanReadsTest < ActiveSupport::TestCase
      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "digitalocean", name: "DigitalOcean")
        @row = @integration.integration_environments.create!
        Digitalocean.store_credentials!(@row, Digitalocean::API_TOKEN => "dop_v1_token")
        @pack = Digitalocean.new(@integration)
      end

      test "api_read only reads, and a path inside an app links the app's page" do
        assert Digitalocean.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        DigitaloceanApi.any_instance.expects(:read).with("/v2/apps/app-1/alerts", { "per_page" => "20" }).returns("alerts" => [ { "id" => "al-1", "phase" => "ACTIVE" } ])

        result = call("path" => "/v2/apps/app-1/alerts", "query" => { "per_page" => 20 })

        assert_match "DigitalOcean answered GET /v2/apps/app-1/alerts?per_page=20.", text(result)
        assert_match "al-1", text(result)
        assert_match "/apps/app-1", text(result)
      end

      test "a database's password never comes back, and a path outside /v2 is said as a failure the agent can fix" do
        DigitaloceanApi.any_instance.stubs(:read).returns("database" => { "id" => "db-1", "connection" => { "host" => "db.example", "password" => "s3cret" } })

        shown = text(call("path" => "/v2/databases/db-1"))
        assert_includes shown, "db.example"
        assert_not_includes shown, "s3cret"
        assert_raises(NativePack::Error) { call("path" => "/apps") }
        assert_raises(PolicyRefusal) { call("path" => "/v2/kubernetes/clusters/k-1/kubeconfig") }
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
