require "test_helper"

module Integrations
  module ReadGuards
    class NetlifyTest < ActiveSupport::TestCase
      test "a GET to a path of the API reads, and the guard guards api_read only" do
        assert Netlify.guards?(ApiReads::TOOL)
        assert_not Netlify.guards?("restore_deploy")
        assert Netlify.reads?(ApiReads::TOOL, "path" => "/sites/site-1/forms", "query" => { "per_page" => 20 })
        assert_raises(Refused) { Netlify.reading(ApiReads::TOOL, "path" => "/sites/../user") }
      end

      test "environment variables, build hooks, hooks and add-on settings are read as names" do
        %w[/accounts/acc-1/env /accounts/acc-1/env/STRIPE_KEY /api/v1/sites/site-1/env /sites/site-1/build_hooks /sites/site-1/build_hooks/bh-1
           /hooks /hooks/h-1 /sites/site-1/service-instances /sites/site-1/services/postgres/instances/i-1].each do |path|
          assert Netlify.secret?(path), path
        end
        %w[/sites /sites/site-1 /sites/site-1/deploys /sites/site-1/forms /user /accounts/acc-1/members].each { |path| assert_not Netlify.secret?(path), path }
      end
    end
  end
end
