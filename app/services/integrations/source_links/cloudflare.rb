module Integrations
  module SourceLinks
    # A Cloudflare result links to the dashboard page for what the call read. Only execute reaches the account, and it
    # runs code, so the page is read off the API paths in that code: DNS records open the zone's DNS page, R2 buckets
    # the account's R2 page. The account and zone come from the call or its answer, and whatever is not known stays a
    # placeholder that Cloudflare's own ?to= link asks the person to choose. The pages are the ones Cloudflare's
    # documentation links to.
    class Cloudflare
      PROVIDER = "cloudflare".freeze
      NAME = "Cloudflare".freeze
      EXECUTE = "execute".freeze
      DASHBOARD = "https://dash.cloudflare.com/?to=/".freeze
      ACCOUNT = ":account".freeze
      ZONE = ":zone".freeze
      ACCOUNT_ID = /\b[0-9a-f]{32}\b/

      # The first match wins, so the more specific paths come first.
      PAGES = [
        [ %r{/dns_records}, "#{ZONE}/dns/records" ],
        [ %r{/ssl|/certificate}, "#{ZONE}/ssl-tls/edge-certificates" ],
        [ %r{/purge_cache|/cache}, "#{ZONE}/caching/configuration" ],
        [ %r{/page_rules}, "#{ZONE}/rules/page-rules" ],
        [ %r{/rulesets|/firewall|/waf}, "#{ZONE}/security/security-rules" ],
        [ %r{/healthchecks}, "#{ZONE}/traffic/health-checks" ],
        [ %r{/r2/}, "r2/overview" ],
        [ %r{/d1/}, "workers/d1" ],
        [ %r{/storage/kv}, "workers/kv/namespaces" ],
        [ %r{/queues}, "workers/queues" ],
        [ %r{/cfd_tunnel|/tunnels}, "tunnels" ],
        [ %r{/workers|/pages/projects}, "workers-and-pages" ],
        [ %r{/audit_logs}, "audit-log" ],
        [ %r{/zones}, ZONE ]
      ].freeze
      ACCOUNT_HOME = "home".freeze

      def initialize(_workspace); end

      def link(tool_name:, arguments:, text: "")
        return unless tool_name == EXECUTE

        asked = arguments.to_h.stringify_keys
        code = asked["code"].to_s
        page = PAGES.find { |pattern, _| code.match?(pattern) }&.last || ACCOUNT_HOME
        path = [ account(asked, code, text), page.sub(ZONE, zone(text)) ].join("/")
        Telemetry::Link.new(provider: NAME, url: "#{DASHBOARD}#{path}")
      end

      private

      def account(asked, code, text)
        [ asked["account_id"], code[%r{/accounts/(#{ACCOUNT_ID})}, 1], text[/"account"\s*:\s*\{[^}]*"id"\s*:\s*"(#{ACCOUNT_ID})"/, 1],
          text[/"account_id"\s*:\s*"(#{ACCOUNT_ID})"/, 1] ].find(&:present?) || ACCOUNT
      end

      def zone(text) = text[/"zone_name"\s*:\s*"([a-z0-9.-]+)"/i, 1] || ZONE
    end
  end
end
