require "test_helper"

module Integrations
  module ReadGuards
    class FlyTest < ActiveSupport::TestCase
      test "a GET to a path of the Machines API reads, and a path outside it is shaped wrong" do
        assert Fly.guards?(ApiReads::TOOL)
        assert_not Fly.guards?("restart_app")
        assert_equal({ "path" => "/v1/apps/web/machines", "query" => { "limit" => "5" } },
                     Fly.reading(ApiReads::TOOL, "path" => "v1/apps/web/machines", "query" => { "limit" => 5 }))
        assert_raises(Refused) { Fly.reading(ApiReads::TOOL, "path" => "/apps/web/machines") }
        assert_not Fly.reads?(ApiReads::TOOL, "path" => "/apps/web/machines")
      end

      test "show_secrets, a Postgres user's credentials and a machine's wait are refused by Firefight's rule" do
        assert_raises(PolicyRefusal) { Fly.reading(ApiReads::TOOL, "path" => "/v1/apps/web/secrets", "query" => { "show_secrets" => true }) }
        assert_raises(PolicyRefusal) { Fly.reading(ApiReads::TOOL, "path" => "/v1/postgres/pg1/users/app/credentials") }
        assert_raises(PolicyRefusal) { Fly.reading(ApiReads::TOOL, "path" => "/v1/apps/web/machines/m1/wait") }
        assert Fly.reads?(ApiReads::TOOL, "path" => "/v1/postgres/pg1/users")
      end

      test "a GraphQL query reads from an app or the organization, and a change or another starting point is not sent" do
        assert Fly.guards?(Fly::GRAPHQL)
        query = "query($app: String!) { a: app(name: $app) { releasesUnprocessed(first: 5, after: \"x\") { nodes { version } } } " \
                "organization(slug: \"acme\") { name } __typename } fragment F on App { id }"
        assert Fly.reads?(Fly::GRAPHQL, "query" => query, "variables" => { "app" => "web" })
        assert_equal [ [ "app", "web" ], [ "organization", "acme" ] ], Fly.roots(query, { "app" => "web" }).map { |root| [ root.field, root.value ] }

        assert_raises(PolicyRefusal) { Fly.reading(Fly::GRAPHQL, "query" => '{ app(name: "web") { id } } mutation { pauseApp(input: {}) { app { id } } }') }
        [ '{ node(id: "x") { id } }', "{ ...F } fragment F on Query { viewer { id } }", '{ app(id: "x") { id } }', '{ app(name: "web", id: "x") { id } }', "", "{ }" ].each do |text|
          assert_raises(Refused, text) { Fly.reading(Fly::GRAPHQL, "query" => text) }
          assert_not Fly.reads?(Fly::GRAPHQL, "query" => text)
        end
      end

      test "a GraphQL query reading secrets, tokens, keys, config or the environment is read as names" do
        [ "{ app(name: \"web\") { secrets { name } } }", "{ app(name: \"web\") { releasesUnprocessed { nodes { configDefinition } } } }",
          "{ organization(slug: \"acme\") { limitedAccessTokens { nodes { name } } } }" ].each { |text| assert Fly.graphql_secret?(text), text }
        assert_not Fly.graphql_secret?("{ app(name: $app) { releasesUnprocessed(first: 5) { nodes { version status imageRef } } } }")
      end

      test "secrets, secret keys, a machine's lease and the token are read as names" do
        %w[/v1/apps/web/secrets /v1/apps/web/secrets/DB /v1/apps/web/secretkeys /v1/apps/web/machines/m1/lease /v1/tokens/current].each do |path|
          assert Fly.secret?(path), path
        end
        %w[/v1/apps/web /v1/apps/web/machines/m1 /v1/postgres/pg1/backups].each { |path| assert_not Fly.secret?(path), path }
      end
    end
  end
end
