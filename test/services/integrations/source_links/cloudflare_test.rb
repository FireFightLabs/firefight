require "test_helper"

module Integrations
  module SourceLinks
    class CloudflareTest < ActiveSupport::TestCase
      ACCOUNT = "0123456789abcdef0123456789abcdef".freeze

      setup do
        @links = Cloudflare.new(workspaces(:slack_workspace_one))
      end

      test "the page follows the API the code called, in the account and zone the answer names" do
        link = @links.link(tool_name: "execute", arguments: { "code" => "cloudflare.request({ path: `/zones/${zone}/dns_records` })" },
                           text: %({"result":[{"zone_name":"firefight.app","account":{"id":"#{ACCOUNT}"}}]}))

        assert_equal "https://dash.cloudflare.com/?to=/#{ACCOUNT}/firefight.app/dns/records", link.url
      end

      test "an account level product opens its own page, and what is not known is left for Cloudflare to ask" do
        r2 = @links.link(tool_name: "execute", arguments: { "code" => "cloudflare.request({ path: `/accounts/#{ACCOUNT}/r2/buckets` })" })
        firewall = @links.link(tool_name: "execute", arguments: { "code" => "cloudflare.request({ path: `/zones/${id}/rulesets` })" })

        assert_equal "https://dash.cloudflare.com/?to=/#{ACCOUNT}/r2/overview", r2.url
        assert_equal "https://dash.cloudflare.com/?to=/:account/:zone/security/security-rules", firewall.url
      end

      test "only a call that reached the account links anywhere" do
        assert_nil @links.link(tool_name: "search", arguments: { "code" => "spec.paths" })
      end
    end
  end
end
