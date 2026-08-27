module Mcp
  module Tools
    class GetIncidentTranscript < Base
      tool_name GET_INCIDENT_TRANSCRIPT
      authorize_as Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS
      description "What people actually said in an incident's channel, in order, with who said it " \
                  "and when. This is the conversation the timeline summarises: the theories that " \
                  "were tested and dropped, why an approach was rejected, what somebody was " \
                  "waiting on. Read it when the timeline tells you what happened and you need to " \
                  "know why. Secrets matching known token formats are redacted before storage, " \
                  "but nothing else is, so treat it as the rawest data in the workspace. Reading " \
                  "it needs the incident_transcripts ability, which is separate from incidents on " \
                  "purpose, and the workspace has to have turned transcript access on. " \
                  "Docs: #{Docs::INCIDENTS}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          incident: { type: "string", description: "Incident UUID or identifier like INC-42" },
          limit: {
            type: "integer",
            description: "How many messages, newest last. Default #{IncidentTranscriptMessage::DEFAULT_MESSAGES}, " \
                         "most #{IncidentTranscriptMessage::MAX_MESSAGES}"
          },
          before: {
            type: "string",
            description: "Message id to read backwards from, for walking a long conversation"
          }
        },
        required: [ "incident" ]
      )

      def self.perform(workspace:, args:)
        blocked_reason = workspace.transcript_access_blocked_reason
        return Mcp::ToolDispatcher.error_response(blocked_reason) if blocked_reason

        incident = IncidentWrite.find!(workspace, args[:incident])
        page = incident.incident_transcript_messages.page(before: args[:before], limit: args[:limit])

        respond(
          incident: incident.identifier,
          messages: page.messages.map { |message| entry(message) },
          more_before: page.more_before
        )
      end

      def self.entry(message)
        {
          message_id: message.message_id,
          thread_id: message.thread_id,
          said_by: message.workspace_membership&.actor_display_name,
          said_at: message.posted_at.utc.iso8601,
          text: message.content,
          redacted: message.scrubbed
        }.compact
      end
    end
  end
end
