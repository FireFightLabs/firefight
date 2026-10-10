module Mcp
  module Tools
    class DeleteHandbookPage < Base
      tool_name DELETE_HANDBOOK_PAGE
      description "Delete a handbook page by its id or title, with its history. Halon stops following it at once. A synced page " \
                  "is removed by stopping its sync on the Handbook page. If the call requires approval, retry the identical " \
                  "call with approval_id once approved. Docs: #{Docs::HANDBOOK}"
      annotations(**DESTRUCTIVE)
      authorize_as Ability::Action::RESOURCE_HANDBOOK, Ability::Action::ACTION_DELETE
      input_schema(
        properties: {
          page: { type: "string", description: "The page's id or title" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: [ "page" ]
      )

      def self.perform(workspace:, args:)
        page = GetHandbookPage.find!(workspace, args[:page])
        HandbookService.new(workspace).delete!(page)
        respond(id: page.id, title: page.title, deleted: true)
      end
    end
  end
end
