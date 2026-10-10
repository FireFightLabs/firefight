require "test_helper"

module Integrations
  module ReadGuards
    class RenderTest < ActiveSupport::TestCase
      test "a GET to a path of the API reads, and the guard guards api_read only" do
        assert Render.guards?(ApiReads::TOOL)
        assert_not Render.guards?("restart_service")
        assert Render.reads?(ApiReads::TOOL, "path" => "/services/srv-1/deploys", "query" => { "limit" => 5 })
        assert_equal({ "path" => "/services", "query" => { "limit" => "5" } }, Render.reading(ApiReads::TOOL, "path" => "services", "query" => { "limit" => 5 }))
      end

      test "a datastore's connection info and a Postgres export are refused by Firefight's rule, and a path shaped wrong is said" do
        %w[/postgres/dpg-1/connection-info /key-value/red-1/connection-info /postgres/dpg-1/export].each do |path|
          assert_not Render.reads?(ApiReads::TOOL, "path" => path)
          assert_raises(PolicyRefusal) { Render.reading(ApiReads::TOOL, "path" => path) }
        end
        assert_raises(Refused) { Render.reading(ApiReads::TOOL, "path" => "/services/../owners") }
        assert_not Render.reads?(ApiReads::TOOL, "path" => "/services?limit=1")
      end

      test "environment variables, secret files, an environment group and registry credentials are read as names" do
        %w[/services/srv-1/env-vars /services/srv-1/secret-files/x /env-groups/evg-1 /registrycredentials].each { |path| assert Render.secret?(path), path }
        %w[/services/srv-1 /env-groups /services/srv-1/deploys].each { |path| assert_not Render.secret?(path), path }
      end
    end
  end
end
