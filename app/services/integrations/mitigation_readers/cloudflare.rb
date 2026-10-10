module Integrations
  module MitigationReaders
    # execute runs a script, so a call is a mitigation when it creates or changes something that decides which traffic
    # reaches a site: a ruleset (WAF custom rules, rate limiting rules), a firewall or access rule, a rate limit, a filter,
    # a user agent block or a zone lockdown. Removing one is not, since undoing that would put the block back.
    module Cloudflare
      TOOL = "execute".freeze
      CHANGING = /\bmethod["']?\s*:\s*["'`](POST|PUT|PATCH)["'`]/i
      RULES = %r{/(rulesets|firewall|access_rules|rate_limits|filters|ua_rules|lockdowns)\b}
      # Firefight's own reading script, which carries its request as JSON.
      WRITTEN_METHOD = /"method"\s*:\s*"(POST|PUT|PATCH)"/

      def self.mitigation?(tool, arguments)
        return false unless tool.name == TOOL

        code = arguments[ReadGuards::Cloudflare::CODE].to_s
        code.match?(RULES) && (code.match?(CHANGING) || code.match?(WRITTEN_METHOD))
      end
    end
  end
end
