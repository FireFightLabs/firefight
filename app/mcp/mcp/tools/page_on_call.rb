module Mcp
  module Tools
    class PageOnCall < Base
      tool_name PAGE_ON_CALL
      authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE
      description "Wake whoever is on call by raising a page in the workspace's on-call tool, on the service or team " \
                  "whose escalation has them on call, with what they need to know. The tool's own escalation pages them, " \
                  "and the page is kept in step with the incident: acknowledging or resolving it on either side reaches " \
                  "the other. Firefight paging raises it, under the workspace's approval rules, and the activity log names " \
                  "you. Use escalate_incident instead when no on-call tool is connected. An incident that is over cannot " \
                  "be paged for. Docs: #{Docs::INCIDENTS}"
      annotations(**WRITE)
      by_hand_words(/\bpage\s+(the\s+)?(on[- ]?call|whoever is on call)\b/i)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          tool: { type: "string", description: "The on-call tool's connection, by its slug. Needed only when there are several" },
          target: { type: "string", description: "What to page in that tool" },
          reason: { type: "string", description: "What the person paged needs before they look: what is broken and since when, the evidence with its links, and the fix you propose" },
          person: { type: "string", description: "Who the tool has on call, by email, when you know (optional)" }
        },
        required: [ "incident", "target", "reason" ]
      )

      choice :tool, from: ->(workspace) { Integrations::Paging.connections(workspace) }
      person :person

      # What a page goes to differs by tool, so each connection's words are listed with it.
      def self.schema_for(workspace)
        schema = super
        targets = Integrations::Paging.connections(workspace).map { |integration| "#{integration.slug}: #{Integrations::Paging.target_words(integration.provider)}" }
        property = schema.dig(:properties, :target)
        property[:description] = [ property[:description], *targets ].join(". ") if property && targets.any?
        schema
      end

      def self.perform_with_principal(workspace:, principal:, args:)
        incident = IncidentWrite.find!(workspace, args[:incident])
        integration = workspace.paging_connection(args[:tool])
        named = Integrations::Paging.connections(workspace).map(&:slug)
        return Mcp::ToolDispatcher.error_response("Name the on-call tool in tool, one of #{named.join(', ')}.") if integration.nil? && named.any?

        service = OnCallSyncService.new(workspace)
        refusal = service.page_blocked_reason(incident, integration)
        return Mcp::ToolDispatcher.error_response(refusal) if refusal

        member = workspace.workspace_memberships.resolve(args[:person].to_s.strip, acting: principal)
        page = service.raise_page!(incident, integration: integration, target: args[:target], details: args[:reason], by: principal,
                                             paged_member: member, paged_email: member&.user&.email || args[:person])
        respond(incident: incident.identifier, tool: integration.display_name, target: page.target, state: page.state,
                page: page.reference, url: page.url, note: page.sync_note)
      end
    end
  end
end
