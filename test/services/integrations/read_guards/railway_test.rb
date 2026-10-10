require "test_helper"

module Integrations
  module ReadGuards
    class RailwayTest < ActiveSupport::TestCase
      QUERY = "query($id: String!) { project(id: $id) { name } }".freeze

      test "a GraphQL query reads, and the guard guards api_read only" do
        assert Railway.guards?(ApiReads::TOOL)
        assert_not Railway.guards?("restart_deployment")
        assert_equal({ "query" => QUERY, "variables" => { "id" => "prj-1" } }, Railway.reading(ApiReads::TOOL, "query" => " #{QUERY} ", "variables" => { "id" => "prj-1" }))
        assert Railway.reads?(ApiReads::TOOL, "query" => "{ me { name } }")
      end

      test "a mutation or a subscription is refused by Firefight's rule, wherever it sits in the document" do
        [ "mutation { deploymentRestart(id: \"d\") }", "subscription { deploymentLogs(deploymentId: \"d\") { message } }",
          "query A { me { name } } mutation B { deploymentRemove(id: \"d\") }" ].each do |text|
          assert_raises(PolicyRefusal, text) { Railway.reading(ApiReads::TOOL, "query" => text) }
          assert_not Railway.reads?(ApiReads::TOOL, "query" => text)
        end
      end

      test "a call shaped wrong is said, so the agent can fix it" do
        assert_raises(Refused) { Railway.reading(ApiReads::TOOL, "query" => " ") }
        assert_raises(Refused) { Railway.reading(ApiReads::TOOL, "query" => QUERY, "variables" => [ "prj-1" ]) }
      end

      test "a query reading variables, config or tokens, under any alias, is read as names" do
        [ "{ variables(projectId: \"p\", environmentId: \"e\") }", "{ v: variablesForServiceDeployment(projectId: \"p\", environmentId: \"e\", serviceId: \"s\") }",
          "{ environment(id: \"e\") { config } }", "{ projectTokens(projectId: \"p\") { edges { node { id } } } }" ].each do |text|
          assert Railway.secret?(text), text
        end
        assert_not Railway.secret?("query($variablesId: String!) { project(id: $variablesId) { name services { edges { node { id name } } } } }")
      end
    end
  end
end
