require "test_helper"

module Integrations
  module Packs
    # Google Cloud's general read, api_read, kept to the projects the connection reads.
    class GoogleCloudReadsTest < ActiveSupport::TestCase
      KEY = { "type" => "service_account", "client_email" => "firefight@acme-prod.iam.gserviceaccount.com", "private_key" => "pem" }.to_json

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "google_cloud", name: "Google Cloud")
        @row = @integration.integration_environments.create!
        GoogleCloud.store_credentials!(@row, GoogleCloud::KEY => KEY)
        @row.store_fields!(GoogleCloud::PROJECT => %w[acme-prod])
        @pack = GoogleCloud.new(@integration)
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        definition = GoogleCloud.tool_definitions.find { |each| each.name == ApiReads::TOOL }

        assert definition.read_only
        assert_equal %w[service path], definition.params_schema["required"]
        assert_equal ReadGuards::GoogleCloud, Provider.for("google_cloud").read_guard
      end

      test "a GET goes to the API's own host inside a project the connection reads, and links its console page" do
        GoogleCloudApi.any_instance.expects(:read).with("cloudbuild", "/v1/projects/acme-prod/builds", { "pageSize" => "5" })
                      .returns("builds" => [ { "id" => "b-1", "status" => "FAILURE", "failureInfo" => { "detail" => "step 2 exited 1" } } ])

        result = call("service" => "cloudbuild", "path" => "/v1/projects/acme-prod/builds", "query" => { "pageSize" => 5 })

        assert_match "Google Cloud answered cloudbuild GET /v1/projects/acme-prod/builds?pageSize=5.", text(result)
        assert_match "step 2 exited 1", text(result)
        assert_includes text(result), "cloud-build/builds?project=acme-prod"
      end

      test "a project the connection does not read is refused before anything is sent" do
        GoogleCloudApi.any_instance.expects(:read).never

        error = assert_raises(PolicyRefusal) { call("service" => "run", "path" => "/v2/projects/someone-else/locations/us-central1/services") }
        assert_match "reaches someone-else", error.message
        assert_raises(PolicyRefusal) { call("service" => "storage", "path" => "/storage/v1/b", "query" => { "project" => "someone-else" }) }
        error = assert_raises(PolicyRefusal) { call("service" => "cloudresourcemanager", "path" => "/v3/projects:search") }
        assert_match "names its project", error.message
      end

      test "a Cloud Run service's environment comes back as names" do
        GoogleCloudApi.any_instance.stubs(:read).returns("template" => { "containers" => [ { "env" => [ { "name" => "DATABASE_URL", "value" => "postgres://u:pw@h/db" } ] } ] })

        shown = text(call("service" => "run", "path" => "/v2/projects/acme-prod/locations/us-central1/services/web"))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "pw@h"
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
