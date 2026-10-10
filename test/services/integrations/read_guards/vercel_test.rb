require "test_helper"

module Integrations
  module ReadGuards
    class VercelTest < ActiveSupport::TestCase
      test "a GET to a path of the API reads, and the guard guards api_read only" do
        assert Vercel.guards?(ApiReads::TOOL)
        assert_not Vercel.guards?("rollback_deployment")
        assert_equal({ "path" => "/v9/projects/shop/domains", "query" => { "limit" => "5" } },
                     Vercel.reading(ApiReads::TOOL, "path" => "v9/projects/shop/domains", "query" => { "limit" => 5 }))
      end

      test "decrypt is never sent, by Firefight's rule, while decrypt false reads" do
        [ true, "true", "1" ].each do |value|
          assert_raises(PolicyRefusal) { Vercel.reading(ApiReads::TOOL, "path" => "/v10/projects/shop/env", "query" => { "decrypt" => value }) }
        end
        assert Vercel.reads?(ApiReads::TOOL, "path" => "/v10/projects/shop/env", "query" => { "decrypt" => false })
      end

      test "environment variables, drains and tokens are read as names" do
        %w[/v10/projects/shop/env /v1/projects/shop/env/env_1 /v1/env /v2/integrations/log-drains /v1/drains /v1/edge-config/ecfg_1/tokens /v5/user/tokens].each do |path|
          assert Vercel.secret?(path), path
        end
        %w[/v9/projects/shop /v13/deployments/dpl_1 /v6/domains /v1/environments].each { |path| assert_not Vercel.secret?(path), path }
      end
    end
  end
end
