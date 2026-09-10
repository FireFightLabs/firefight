module Mcp
  module Tools
    module PostmortemPayloads
      # The dispatcher's generic "Not found in this workspace" would hide that the
      # incident exists and the postmortem does not.
      def self.with_postmortem(workspace, reference)
        postmortem = IncidentWrite.find!(workspace, reference).postmortem
        unless postmortem
          return Mcp::ToolDispatcher.error_response(
            "#{reference} has no postmortem yet. Start one with start_postmortem."
          )
        end

        yield postmortem
      end

      def self.summary(postmortem)
        {
          incident: postmortem.incident.identifier,
          title: postmortem.title,
          status: postmortem.status,
          generation_state: postmortem.generation_state,
          written_by: postmortem.generated_by&.actor_display_name,
          version: postmortem.content_version,
          updated_at: postmortem.updated_at.utc.iso8601
        }.compact
      end
    end
  end
end
