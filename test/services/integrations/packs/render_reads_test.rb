require "test_helper"

module Integrations
  module Packs
    # Render's general read, api_read, kept to the workspaces the connection reads.
    class RenderReadsTest < ActiveSupport::TestCase
      WEB_PAGE = "https://dashboard.render.com/web/srv-web".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
        @row = @integration.integration_environments.create!
        Render.store_credentials!(@row, Render::API_KEY => "rnd_key")
        @row.store_fields!(Render::WORKSPACE => %w[tea-1])
        @pack = Render.new(@integration)
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        definition = Render.tool_definitions.find { |each| each.name == ApiReads::TOOL }

        assert definition.read_only
        assert_equal %w[path], definition.params_schema["required"]
        assert_equal ReadGuards::Render, Provider.for("render").read_guard
      end

      test "a deeper path is read inside a service of this workspace, answering with the service's page" do
        RenderApi.any_instance.expects(:read).with("/services/srv-web", {}).returns("id" => "srv-web", "ownerId" => "tea-1", "dashboardUrl" => WEB_PAGE)
        RenderApi.any_instance.expects(:read).with("/services/srv-web/jobs", { "limit" => "5" }).returns([ { "job" => { "id" => "job-1", "status" => "succeeded" } } ])

        result = call("path" => "/services/srv-web/jobs", "query" => { "limit" => 5 })

        assert_match "Render answered GET /services/srv-web/jobs?limit=5.", text(result)
        assert_match "job-1", text(result)
        assert_includes text(result), WEB_PAGE
      end

      test "a service of a workspace the connection does not read is refused before it is read" do
        RenderApi.any_instance.expects(:read).with("/services/srv-other", {}).returns("id" => "srv-other", "ownerId" => "tea-2")
        RenderApi.any_instance.expects(:read).with("/services/srv-other/deploys", anything).never

        error = assert_raises(PolicyRefusal) { call("path" => "/services/srv-other/deploys") }
        assert_match "reaches tea-2", error.message
      end

      test "a list that names another workspace is refused with how to keep it to one, and an ownerId it does not read is refused at once" do
        RenderApi.any_instance.stubs(:read).with("/services", {}).returns([ { "service" => { "id" => "srv-a", "ownerId" => "tea-1" } }, { "service" => { "id" => "srv-b", "ownerId" => "tea-2" } } ])

        error = assert_raises(PolicyRefusal) { call("path" => "/services") }
        assert_match "Pass ownerId in query", error.message
        assert_raises(PolicyRefusal) { call("path" => "/services", "query" => { "ownerId" => "tea-2" }) }
      end

      test "environment variables come back as their names, and connection info is never read" do
        RenderApi.any_instance.stubs(:read).with("/services/srv-web", {}).returns("id" => "srv-web", "ownerId" => "tea-1")
        RenderApi.any_instance.stubs(:read).with("/services/srv-web/env-vars", {}).returns([ { "envVar" => { "key" => "DATABASE_URL", "value" => "postgres://u:pw@h/db" } } ])
        RenderApi.any_instance.expects(:read).with("/postgres/dpg-1/connection-info", anything).never

        shown = text(call("path" => "/services/srv-web/env-vars"))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "pw@h"
        assert_raises(PolicyRefusal) { call("path" => "/postgres/dpg-1/connection-info") }
      end

      test "a path shaped wrong is said as a failure the agent can fix" do
        error = assert_raises(NativePack::Error) { call("path" => "/services/../owners") }
        assert_match "plain API path", error.message
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
