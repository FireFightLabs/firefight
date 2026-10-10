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

      test "secrets, secret keys, a machine's lease and the token are read as names" do
        %w[/v1/apps/web/secrets /v1/apps/web/secrets/DB /v1/apps/web/secretkeys /v1/apps/web/machines/m1/lease /v1/tokens/current].each do |path|
          assert Fly.secret?(path), path
        end
        %w[/v1/apps/web /v1/apps/web/machines/m1 /v1/postgres/pg1/backups].each { |path| assert_not Fly.secret?(path), path }
      end
    end
  end
end
