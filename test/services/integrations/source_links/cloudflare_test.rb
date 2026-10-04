require "test_helper"

module Integrations
  module SourceLinks
    class CloudflareTest < ActiveSupport::TestCase
      ACCOUNT = "0123456789abcdef0123456789abcdef".freeze

      setup do
        @links = Cloudflare.new(ConnectionSettings.of(Integration.new(workspace: workspaces(:slack_workspace_one)).integration_environments.build))
      end

      test "a fully known page opens directly, from the one path the code requested and the zone the answer names" do
        link = @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/zones/${zone}/dns_records` })", "account_id" => ACCOUNT },
                           text: %({"result":[{"zone_name":"firefight.app"}]}))

        assert_equal "https://dash.cloudflare.com/#{ACCOUNT}/firefight.app/dns/records", link.url
      end

      test "an account level product opens its own page, and what is not known is left for Cloudflare to ask" do
        r2 = @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: '/accounts/#{ACCOUNT}/r2/buckets' })" })
        firewall = @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/zones/${id}/rulesets` })" })

        assert_equal "https://dash.cloudflare.com/#{ACCOUNT}/r2/overview", r2.url
        assert_equal "https://dash.cloudflare.com/?to=/:account/:zone/security/security-rules", firewall.url
      end

      test "no link for a page it cannot name: several paths, one the table does not know, or an answer across several zones" do
        several = "cloudflare.request({ path: `/zones/${a}/dns_records` }); cloudflare.request({ path: `/accounts/${b}/queues` })"
        many_zones = %([{"zone_name":"a.app"},{"zone_name":"b.app"}])

        assert_nil @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => several })
        assert_nil @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/zones/${id}/settings/cache_level` })" })
        assert_nil @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/user/tokens` })" })
        assert_equal "https://dash.cloudflare.com/?to=/:account/:zone/dns/records",
                     @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/zones/${id}/dns_records` })" }, text: many_zones).url
      end

      test "an account id that is not one is never put in the address, and only execute reaches the account" do
        link = @links.link(tool_name: Cloudflare::EXECUTE, arguments: { "code" => "cloudflare.request({ path: `/accounts/${a}/queues` })", "account_id" => "../evil" })

        assert_equal "https://dash.cloudflare.com/?to=/:account/workers/queues", link.url
        assert_nil @links.link(tool_name: "search", arguments: { "code" => "spec.paths" })
      end
    end
  end
end
