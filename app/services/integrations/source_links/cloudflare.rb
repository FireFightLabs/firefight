module Integrations
  module SourceLinks
    # A Cloudflare result links to the dashboard page for what the call read. Only execute reaches the account, and it
    # runs code, so the page comes from the one API path that code requested. Code that calls several paths, or one the
    # table does not know, gets no link rather than a page it did not read. The pages are the dashboard deep links
    # Cloudflare's documentation uses (its DashButton component, in the cloudflare-docs repository).
    class Cloudflare
      PROVIDER = MapReaders::Cloudflare::PROVIDER
      NAME = "Cloudflare".freeze
      EXECUTE = "execute".freeze
      DASHBOARD = "https://dash.cloudflare.com/".freeze
      DEEP_LINK = "https://dash.cloudflare.com/?to=/".freeze
      ACCOUNT = ":account".freeze
      ZONE = ":zone".freeze
      ACCOUNT_ID = /\A[0-9a-f]{32}\z/
      # The path handed to cloudflare.request, in quotes or a template string.
      REQUESTED_PATH = /path\s*:\s*[`'"]([^`'"]+)[`'"]/

      # By the API path's segments after /zones/<id> or /accounts/<id>, the dashboard page that shows them.
      ZONE_PAGES = {
        "dns_records" => "dns/records", "ssl" => "ssl-tls/edge-certificates", "custom_certificates" => "ssl-tls/edge-certificates",
        "purge_cache" => "caching/configuration", "cache" => "caching/configuration", "pagerules" => "rules/page-rules",
        "rulesets" => "security/security-rules", "firewall" => "security/security-rules", "healthchecks" => "traffic/health-checks"
      }.freeze
      ACCOUNT_PAGES = {
        "r2" => "r2/overview", "d1" => "workers/d1", "storage" => "workers/kv/namespaces", "queues" => "workers/queues",
        "cfd_tunnel" => "tunnels", "workers" => "workers-and-pages", "pages" => "workers-and-pages", "audit_logs" => "audit-log"
      }.freeze

      def initialize(_workspace); end

      def link(tool_name:, arguments:, text: "")
        return unless tool_name == EXECUTE

        asked = arguments.to_h.stringify_keys
        paths = asked["code"].to_s.scan(REQUESTED_PATH).flatten.uniq
        return unless paths.size == 1

        scope, section = paths.first.delete_prefix("/").split("/").values_at(0, 2)
        account = account(asked, paths.first, text)
        path = case scope
        when "zones" then ZONE_PAGES[section] && [ account, one(text, "zone_name") || ZONE, ZONE_PAGES[section] ]
        when "accounts" then ACCOUNT_PAGES[section] && [ account, ACCOUNT_PAGES[section] ]
        end
        return unless path

        Telemetry::Link.new(provider: NAME, url: url(path))
      end

      private

      # A fully known page opens directly. Otherwise Cloudflare's own deep link asks the person for what is missing.
      def url(path)
        joined = path.join("/")
        path.include?(ACCOUNT) || path.include?(ZONE) ? "#{DEEP_LINK}#{joined}" : "#{DASHBOARD}#{joined}"
      end

      def account(asked, path, text)
        [ asked["account_id"].to_s, path.split("/")[2].to_s, one(text, "account_id").to_s ].find { |candidate| candidate.match?(ACCOUNT_ID) } || ACCOUNT
      end

      # A field's value when the answer names exactly one, so a list across several zones is not linked to its first.
      def one(text, field)
        found = text.scan(/"#{field}"\s*:\s*"([^"]+)"/).flatten.uniq
        found.first if found.size == 1
      end
    end
  end
end
