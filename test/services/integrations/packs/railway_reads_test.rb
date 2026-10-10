require "test_helper"

module Integrations
  module Packs
    # Railway's general read, api_read, one GraphQL query kept to the projects the connection reads.
    class RailwayReadsTest < ActiveSupport::TestCase
      QUERY = "query($id: String!) { project(id: $id) { id name volumes { edges { node { id name } } } } }".freeze

      setup do
        @integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "railway", name: "Railway")
        @row = @integration.integration_environments.create!
        Railway.store_credentials!(@row, Railway::API_TOKEN => "rw-token")
        @row.store_fields!(Railway::PROJECT => %w[prj-1], Railway::ENVIRONMENT => "production")
        @pack = Railway.new(@integration)
      end

      test "api_read only reads, so a member holds it without a grant and a chat never asks before it" do
        assert Railway.tool_definitions.find { |each| each.name == ApiReads::TOOL }.read_only
        assert_equal ReadGuards::Railway, Provider.for("railway").read_guard
      end

      test "a query in a project the connection reads is answered, linking the project's page" do
        RailwayApi.any_instance.expects(:read).with(QUERY, { "id" => "prj-1" }).returns("project" => { "id" => "prj-1", "name" => "shop", "volumes" => { "edges" => [] } })

        shown = text(call("query" => QUERY, "variables" => { "id" => "prj-1" }))
        assert_match "Railway answered the query", shown
        assert_includes shown, "shop"
        assert_includes shown, "https://railway.com/project/prj-1"
      end

      test "another project, named by a variable, in the query's words or in the answer, is refused" do
        RailwayApi.any_instance.expects(:read).never
        assert_raises(PolicyRefusal) { call("query" => "query($projectId: String!) { deployments(input: { projectId: $projectId }) { edges { node { id } } } }", "variables" => { "projectId" => "prj-2" }) }
        assert_raises(PolicyRefusal) { call("query" => "{ project(id: \"prj-2\") { name } }") }
      end

      test "an answer naming another project is not shown" do
        RailwayApi.any_instance.stubs(:read).returns("projects" => { "edges" => [ { "node" => { "id" => "prj-1" } }, { "node" => { "id" => "prj-2" } } ] })

        assert_match "reaches prj-2", assert_raises(PolicyRefusal) { call("query" => "{ projects { edges { node { id } } } }") }.message
      end

      test "a mutation is refused, and variables read under an alias come back as names only" do
        RailwayApi.any_instance.expects(:read).with(regexp_matches(/mutation/), anything).never
        assert_raises(PolicyRefusal) { call("query" => "mutation { deploymentRestart(id: \"d\") }") }

        RailwayApi.any_instance.stubs(:read).returns("v" => { "DATABASE_URL" => "postgres://u:pw@h/db" })
        shown = text(call("query" => "{ v: variables(projectId: \"prj-1\", environmentId: \"e\") }"))
        assert_includes shown, "DATABASE_URL"
        assert_not_includes shown, "pw@h"
      end

      private

      def call(arguments) = @pack.call(ApiReads::TOOL, environment_row: @row, arguments: arguments)

      def text(result) = result["content"].map { |part| part["text"] }.join("\n")
    end
  end
end
