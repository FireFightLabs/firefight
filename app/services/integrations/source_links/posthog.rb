module Integrations
  module SourceLinks
    # PostHog's answers carry the page they came from as _posthogUrl, which PostHog asks an agent to hand on as it is
    # (PostHog/posthog, services/mcp/src/templates/sections/url-patterns.md, and withPostHogUrl in src/tools/tool-utils.ts).
    # The one at the top of the answer becomes the link line. The answer is TOON text by default (src/lib/response.ts),
    # where a top level field is a line of its own with no indent, or JSON when asked. PostHog's US server sends a login
    # to whichever region the account is in, so a connection made under US can hold an EU account. A page on any of
    # PostHog's region sites is used, and anything else is not. An answer without one, such as a log search, gets no
    # link, since only PostHog's server knows the project behind the connection.
    class Posthog
      NAME = Capabilities::Posthog::PROVIDER_NAME
      FIELD = "_posthogUrl".freeze
      TOON_FIELD = /^#{FIELD}: "?(?<url>[^"\s]+)"?$/o

      def initialize(settings)
        @sites = [ settings.site, *settings.region_sites ].compact.map { |site| site.chomp("/") }.uniq
      end

      def link(tool_name:, arguments:, text: "")
        url = from_json(text) || text.to_s[TOON_FIELD, :url]
        Telemetry::Link.new(provider: NAME, url: url) if url && @sites.any? { |site| url.start_with?("#{site}/") }
      end

      private

      def from_json(text)
        parsed = JSON.parse(text.to_s)
        parsed[FIELD] if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
