module Mcp
  module Tools
    class UpsertHandbookPage < Base
      tool_name UPSERT_HANDBOOK_PAGE
      description "Add a handbook page, or change one by its id or title. Halon reads the handbook at the start of every chat " \
                  "and investigation. To change a page, pass page and only what changes, with wording_id from get_handbook_page " \
                  "so an edit made over someone else's is refused rather than written over it. A page with incident_role says " \
                  "who directs Halon in an incident, and the handbook holds one. A synced page is changed at its source, not " \
                  "here. If the call requires approval, retry the identical call with approval_id once approved. Docs: #{Docs::HANDBOOK}"
      annotations(**WRITE)
      input_schema(
        properties: {
          page: { type: "string", description: "The id or title of the page to change. Omit to add a page. An unknown page is an error, not an add" },
          title: { type: "string", description: "The page's title, required to add one, at most #{Chat::HandbookPage::TITLE_LIMIT} characters" },
          text: { type: "string", description: "The whole page in Markdown, at most #{Chat::HandbookPage::TEXT_LIMIT} characters" },
          incident_role: { type: "string", description: "The slug of the incident role Halon takes direction from, only for the page saying who directs Halon" },
          freeze_windows: {
            type: "array",
            description: "Every freeze window the page sets, replacing the ones it has. Plans never run inside one. Omit to keep them",
            items: {
              type: "object",
              properties: {
                name: { type: "string", description: "Such as Friday afternoons or End of year" },
                repeat: { type: "string", enum: Workspace::FreezeWindows::REPEATS, description: "weekly, or once between two moments" },
                time_zone: { type: "string", description: "An IANA time zone such as Europe/Berlin, which every time is read in" },
                start_day: { type: "integer", minimum: 0, maximum: 6, description: "For weekly, the day it starts, 0 for Sunday" },
                start_time: { type: "string", description: "For weekly, the time it starts, HH:MM" },
                end_day: { type: "integer", minimum: 0, maximum: 6, description: "For weekly, the day it ends, 0 for Sunday" },
                end_time: { type: "string", description: "For weekly, the time it ends, HH:MM" },
                starts_at: { type: "string", description: "For once, when it starts, YYYY-MM-DDTHH:MM in time_zone" },
                ends_at: { type: "string", description: "For once, when it ends, YYYY-MM-DDTHH:MM in time_zone" },
                lifted_by: { type: "string", description: "Who may lift it, such as the CTO" }
              },
              required: %w[name repeat time_zone]
            }
          },
          wording_id: { type: "string", description: "The wording_id get_handbook_page gave, to refuse an edit made over someone else's" },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.authorization(workspace, args)
        target = args[:page].present? ? GetHandbookPage.find!(workspace, args[:page]) : nil
        [ Ability::Action::RESOURCE_HANDBOOK, target ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE ]
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        service = HandbookService.new(workspace)
        author = principal.is_a?(WorkspaceMembership) ? principal : nil
        role = args[:incident_role].present? ? workspace.incident_roles.active.find_by!(slug: args[:incident_role].to_s) : nil
        if args[:page].present?
          page = GetHandbookPage.find!(workspace, args[:page])
          written = service.update!(page, text: args.key?(:text) ? args[:text] : page.text, title: args[:title], by: author,
                                          wording_id: args[:wording_id].presence || page.current_wording&.id,
                                          incident_role: page.directing? ? (role || page.current_wording&.incident_role) : nil,
                                          freeze_windows: args.key?(:freeze_windows) ? Array(args[:freeze_windows]) : page.current_wording&.freeze_windows)
          return refuse(error: "Someone changed #{page.title} first. Read it again with get_handbook_page before changing it.") unless written
        else
          page = service.create!(title: args[:title], text: args[:text], by: author, incident_role: role, freeze_windows: role ? [] : Array(args[:freeze_windows]))
        end
        page.reload
        respond(ListHandbookPages.summary(page).merge(wording_id: page.current_wording&.id))
      end
    end
  end
end
