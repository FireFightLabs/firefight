module Mcp
  module Tools
    # The answer to a question ask_halon was still working on, from the caller's own chat. It waits on the turn the
    # same way ask_halon does.
    class GetHalonAnswer < Base
      tool_name FirefightTools::GET_HALON_ANSWER
      # Whoever may ask may read what they were told, so a key that can ask is never left without its answer.
      authorize_as Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE
      # Reading an answer spends nothing, so an approval rule on asking never holds it.
      never_held
      description "Wait for the answer to a question you asked with #{FirefightTools::ASK_HALON} that was still working. Give the " \
                  "conversation_id it returned. Waits up to #{HalonAnswer::WAIT.inspect}, and answers with the same " \
                  "statuses as #{FirefightTools::ASK_HALON}: #{HalonAnswer::STATUS_ANSWERED}, #{HalonAnswer::STATUS_WAITING} for a " \
                  "confirmation, or #{HalonAnswer::STATUS_WORKING} again, so call it again. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          conversation_id: { type: "string", description: "The conversation_id #{FirefightTools::ASK_HALON} returned" }
        },
        required: [ "conversation_id" ]
      )

      def self.perform_with_principal(workspace:, principal:, args:)
        conversation = workspace.conversations.find_by!(
          id: args[:conversation_id].to_s, kind: Conversation::KIND_MCP, started_by: principal
        )
        HalonAnswer.after_waiting(conversation)
      end
    end
  end
end
