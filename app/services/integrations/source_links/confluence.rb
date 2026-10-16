module Integrations
  module SourceLinks
    # A Confluence result about one page links to it, from the page's own links in the answer: _links.webui, the page's
    # path in Confluence's app, under _links.base, the site's Confluence address, as Confluence's REST API gives every
    # page (developer.atlassian.com/cloud/confluence/rest/v2/api-group-page). An answer without a base takes the site from
    # the call's cloudId when it names the site by its address, which Atlassian's server accepts in place of the id. An
    # answer without the page's own links gets none, since its address would have to be guessed.
    class Confluence
      NAME = "Confluence".freeze
      CLOUD_ID = "cloudId".freeze
      # Tools are named as discovery stores them, lowercased from Atlassian's own names.
      PAGE_TOOLS = %w[getconfluencecontent createconfluencecontent updateconfluencecontent].freeze
      WIKI = "/wiki".freeze
      ADDRESS = %r{\Ahttps://[^/\s]+/\S*\z}

      def initialize(_settings); end

      def link(tool_name:, arguments:, text: "")
        return unless PAGE_TOOLS.include?(tool_name)

        url = self.class.page_url(self.class.answer_of(text), arguments.to_h.stringify_keys[CLOUD_ID])
        Telemetry::Link.new(provider: NAME, url: url) if url
      end

      # The page's address from its _links, or nil.
      def self.page_url(page, cloud_id)
        links = page.is_a?(Hash) ? page["_links"] : nil
        webui = links.is_a?(Hash) ? links["webui"].to_s : ""
        return unless webui.start_with?("/")

        base = links["base"].to_s.presence || AtlassianSite.of(cloud_id)&.then { |site| "https://#{site}#{WIKI}" }
        url = "#{base.to_s.chomp('/')}#{webui}"
        url if url.match?(ADDRESS)
      end

      # The answer's text read as one JSON object, or nil.
      def self.answer_of(text)
        parsed = JSON.parse(text.to_s)
        parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
