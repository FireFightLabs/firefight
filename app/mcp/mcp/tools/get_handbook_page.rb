module Mcp
  module Tools
    class GetHandbookPage < Base
      tool_name GET_HANDBOOK_PAGE
      authorize_as Ability::Action::RESOURCE_HANDBOOK
      description "Read one handbook page whole, by its id or its title: its text, its kind, the role it names when it says who " \
                  "directs Halon, where a synced page comes from, and wording_id, which upsert_handbook_page takes to refuse " \
                  "an edit made over someone else's. Docs: #{Docs::HANDBOOK}"
      annotations(**READ_ONLY)
      own_words
      input_schema(
        properties: {
          page: { type: "string", description: "The page's id or title" }
        },
        required: [ "page" ]
      )

      def self.perform(workspace:, args:)
        page = find!(workspace, args[:page])
        respond(ListHandbookPages.summary(page).merge(text: page.text, wording_id: page.current_wording&.id))
      end

      # By id, or by title whatever its case.
      def self.find!(workspace, reference)
        pages = Chat::HandbookPage.where(workspace: workspace).includes(:source, current_wording: :incident_role)
        wanted = reference.to_s.squish
        pages.find_by(id: wanted.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) ? wanted : nil) ||
          pages.where("lower(title) = ?", wanted.downcase).first || raise(ActiveRecord::RecordNotFound)
      end
    end
  end
end
