require "test_helper"

module Integrations
  module Packs
    # Azure's general read, api_read, kept to the subscriptions the connection reads.
    class AzureReadsTest < ActiveSupport::TestCase
      SUBSCRIPTION = "11111111-2222-3333-4444-555555555555".freeze
      APP = "/subscriptions/#{SUBSCRIPTION}/resourceGroups/shop/providers/Microsoft.App/containerApps/api".freeze
      PORTAL = 'https://portal.azure.com/#@contoso.onmicrosoft.com/resource'.freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure")
        @row = @integration.integration_environments.create!
        Azure.store_credentials!(@row, Azure::SECRET => "s3cret")
        @row.store_fields!(Azure::TENANT => "contoso.onmicrosoft.com", Azure::CLIENT => "22222222-2222-3333-4444-555555555555", Azure::SUBSCRIPTION => SUBSCRIPTION)
        @pack = Azure.new(@integration)
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        definition = Azure.tool_definitions.find { |each| each.name == ApiReads::TOOL }

        assert definition.read_only
        assert_equal ReadGuards::Azure, Provider.for("azure").read_guard
      end

      test "a GET goes to Resource Manager with its api-version, and links the portal page of the resource it reads in" do
        AzureApi.any_instance.expects(:get).with("#{APP}/revisions", "2024-03-01", {})
                .returns("value" => [ { "name" => "api--v3", "properties" => { "healthState" => "Unhealthy", "runningState" => "Failed",
                                                                                 "template" => { "containers" => [ { "env" => [ { "name" => "DB_URL", "value" => "postgres://u:pw@h/db" } ] } ] } } } ])

        shown = text(call("path" => "#{APP}/revisions", "query" => { "api-version" => "2024-03-01" }))

        assert_match "Azure answered GET #{APP}/revisions?api-version=2024-03-01.", shown
        assert_match "Unhealthy", shown
        assert_includes shown, "DB_URL"
        assert_not_includes shown, "pw@h"
        assert_includes shown, "#{PORTAL}#{APP}/overview"
      end

      test "another subscription is refused before anything is sent" do
        AzureApi.any_instance.expects(:get).never

        error = assert_raises(PolicyRefusal) { call("path" => "/subscriptions/99999999-0000-0000-0000-000000000000/resourceGroups", "query" => { "api-version" => "2021-04-01" }) }
        assert_match "reaches 99999999-0000-0000-0000-000000000000", error.message
      end

      test "a missing api-version is said as a failure the agent can fix" do
        error = assert_raises(NativePack::Error) { call("path" => APP) }
        assert_match "api-version", error.message
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
