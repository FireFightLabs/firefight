module Mcp
  module Tools
    # One question, one answer, as whoever the key belongs to. A person's key acts as the person, an
    # agent's token as the agent, a service key as itself. The chat is kept, so questions carry on.
    # The turn runs in the background like any other chat, and the call waits on it a while (HalonAnswer).
    class AskHalon < Base
      tool_name ASK_HALON
      # The same permission as asking in the dashboard, since a question spends money.
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      description "Ask Halon, Firefight's agent, a question. It answers from incidents, alerts, the catalog, runbooks " \
                  "and the connected tools, and can act in Firefight with exactly the permissions of whoever this key " \
                  "belongs to. Name an incident to ask about it. Most answers take ten seconds to a minute, and this " \
                  "call waits up to #{HalonAnswer::WAIT.inspect} for one. If Halon is still working, the status is " \
                  "#{HalonAnswer::STATUS_WORKING}, and #{GET_HALON_ANSWER} with the conversation_id waits for the " \
                  "answer. A change that needs confirming is not made, and the answer says what is waiting and on " \
                  "whom. Docs: #{Docs::MCP_SERVER}"
      annotations(**WRITE)
      input_schema(
        properties: {
          question: { type: "string", description: "What you want to know or have done, in plain words" },
          incident: { type: "string", description: "Incident UUID or identifier like INC-42 to ask about (optional)" }
        },
        required: [ "question" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        question = args[:question].to_s.strip
        return Mcp::ToolDispatcher.error_response("Ask something first.") if question.blank?

        unavailable = Investigation.unavailable_reason(workspace)
        return Mcp::ToolDispatcher.error_response(unavailable) if unavailable

        incident = IncidentWrite.find!(workspace, args[:incident]) if args[:incident].present?
        conversation = Conversation.for_mcp!(workspace: workspace, principal: principal, incident: incident)
        return Mcp::ToolDispatcher.error_response(still_answering(conversation)) if conversation.answer_owed?

        Conversation::Asking.ask(conversation, question, asker: principal)
        respond(HalonAnswer.after_waiting(conversation))
      end

      # A question saved mid turn would land between a tool call and its result, which a model provider refuses.
      def self.still_answering(conversation)
        "Halon is still answering your last question in this chat. Call #{GET_HALON_ANSWER} with conversation_id " \
          "#{conversation.id} to wait for it, then ask again."
      end
      private_class_method :still_answering
    end
  end
end
