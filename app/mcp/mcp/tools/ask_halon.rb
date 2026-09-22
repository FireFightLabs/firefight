module Mcp
  module Tools
    # One question, one answer, as whoever the key belongs to. A person's key acts as the person, an
    # agent's token as the agent, a service key as itself. The chat is kept, so questions carry on.
    class AskHalon < Base
      STATUS_ANSWERED = "answered"
      STATUS_WAITING = "waiting"

      tool_name ASK_HALON
      # The same permission as asking in the dashboard, since a question spends money.
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      description "Ask Halon, Firefight's agent, a question and wait for the answer, which takes ten seconds " \
                  "to a minute. It answers from incidents, alerts, the catalog, runbooks and the connected " \
                  "tools, and can act in Firefight with exactly the permissions of whoever this key belongs " \
                  "to. Name an incident to ask about it. A change that needs confirming is not made, and the " \
                  "answer says what is waiting and on whom. Docs: #{Docs::MCP_SERVER}"
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
        conversation.ask!(question)

        runner = Conversation::Runner.new(conversation, asker: principal)
        outcome = runner.run
        return respond(waiting(conversation)) if outcome.status == FirefightAi::AgentLoop::STATUS_WAITING

        respond(status: STATUS_ANSWERED, answer: runner.reply, conversation_id: conversation.id)
      end

      # What the agent paused on, in the words the dashboard would show, so the caller can tell the person.
      def self.waiting(conversation)
        questions = conversation.chat.awaiting_decision.map { |call| Chat::Tools.confirmation(call).question }
        {
          status: STATUS_WAITING, conversation_id: conversation.id, waiting_on: questions,
          answer: "Halon needs a confirmation before it can go on: #{questions.to_sentence} " \
                  "Confirm it in Firefight, then ask again."
        }
      end
      private_class_method :waiting
    end
  end
end
