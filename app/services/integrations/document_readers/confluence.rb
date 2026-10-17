module Integrations
  module DocumentReaders
    # Reads one Confluence page through Atlassian's Rovo MCP server. getConfluenceContent takes the site as cloudId (its
    # address serves in place of its id), the page's id as content_id and markdown as content_format, as Atlassian's own
    # search skill calls it (atlassian/atlassian-mcp-server, skills/search-company-knowledge). A page is named by its
    # link, which holds both the site and the id (/wiki/spaces/ENG/pages/123/Title, or ?pageId=123), or by its id alone
    # when the connection reaches one site, read from getAccessibleAtlassianResources. The page's title and body are read
    # from the answer, and an answer whose shape this does not read is kept whole rather than lost.
    class Confluence < RemoteReader
      NAME = "Confluence".freeze
      CONTENT = "getconfluencecontent".freeze
      RESOURCES = "getaccessibleatlassianresources".freeze
      MARKDOWN = "markdown".freeze
      PAGE_PATH = %r{/pages/(\d+)}
      PAGE_QUERY = /[?&]pageId=(\d+)/
      BARE_ID = /\A\d+\z/
      BODY_KEYS = %w[markdown value body content text].freeze
      # Confluence's address for a page by its id, which it moves to the page's own address.
      VIEW_PAGE = "/wiki/pages/viewpage.action?pageId=".freeze

      def page(reference)
        given = reference.to_s.strip
        id = given[PAGE_PATH, 1] || given[PAGE_QUERY, 1] || given[BARE_ID]
        raise Integrations::Error, "Paste the Confluence page's link, such as https://acme.atlassian.net/wiki/spaces/ENG/pages/123456/Runbook." unless id

        site = given.include?("://") ? AtlassianSite.of(given) : only_site
        raise Integrations::Error, "#{given} is not a Confluence page's link." unless site

        result = call(CONTENT, { "cloudId" => site, "content_id" => id, "content_format" => MARKDOWN }, "the page #{id}")
        raise Integrations::Error, "getConfluenceContent is switched off on #{settings&.name || 'this connection'}, so the page cannot be read." if result.nil?

        refused!(CONTENT, result)
        answer = Capabilities::Answers.data(result)
        answer = {} unless answer.is_a?(Hash)
        text = body_of(answer) || Capabilities::Answers.text(result)
        url = SourceLinks::Confluence.page_url(answer, site) || (given if given.start_with?("https://")) || "https://#{site}#{VIEW_PAGE}#{id}"
        Documents::Page.new(title: answer["title"].to_s.strip.presence || "Confluence page", text: text.to_s.strip, url: url)
      end

      private

      # The one site the connection reaches, since a page's id alone does not say which. Raises when it reaches none or
      # several.
      def only_site
        result = call(RESOURCES, {}, "the sites this connection reaches")
        raise Integrations::Error, "getAccessibleAtlassianResources is switched off, so paste the page's link rather than its id." if result.nil?

        refused!(RESOURCES, result)
        sites = Array(Capabilities::Answers.data(result)).filter_map { |site| AtlassianSite.of(site["url"]) if site.is_a?(Hash) }.uniq
        return sites.first if sites.one?

        raise Integrations::Error, "This connection reaches #{sites.size} Confluence sites, so paste the page's link rather than its id."
      end

      # The page's body, as a string at the top of the answer or under its body.
      def body_of(answer)
        BODY_KEYS.each do |key|
          value = answer[key]
          return value if value.is_a?(String) && value.present?
          next unless value.is_a?(Hash)

          found = BODY_KEYS.lazy.filter_map { |inner| value[inner] if value[inner].is_a?(String) && value[inner].present? }.first
          found ||= value.values.lazy.filter_map { |nested| nested["value"] if nested.is_a?(Hash) && nested["value"].is_a?(String) }.first
          return found if found
        end
        nil
      end
    end
  end
end
