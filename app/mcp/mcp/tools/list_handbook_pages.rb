module Mcp
  module Tools
    class ListHandbookPages < Base
      tool_name LIST_HANDBOOK_PAGES
      authorize_as Ability::Action::RESOURCE_HANDBOOK
      description "List this workspace's handbook pages in order: how the workspace works as its people wrote it, such as how " \
                  "it releases, who owns what and when changes are frozen. Each page has its id, title, kind (written, " \
                  "directing for who directs Halon in an incident, or synced from a repository or a document) and link. " \
                  "Read one whole with get_handbook_page. Docs: #{Docs::HANDBOOK}"
      annotations(**READ_ONLY)
      own_words
      input_schema(properties: {}, required: [])

      def self.perform(workspace:, args:)
        pages = Chat::HandbookPage.where(workspace: workspace).ordered.includes(:source, current_wording: :incident_role)
        respond(pages: pages.map { |page| summary(page) })
      end

      def self.summary(page)
        {
          id: page.id, title: page.title, kind: page.kind, url: page.url, characters: page.text.length,
          incident_role: (page.current_wording&.directing_role&.slug if page.directing?),
          source: (page.source.label if page.source), freeze_windows: page.freeze_rules.map(&:stored).presence
        }.compact
      end
    end
  end
end
