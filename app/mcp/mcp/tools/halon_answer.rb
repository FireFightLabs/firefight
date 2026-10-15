module Mcp
  module Tools
    # Where an outside agent's turn with Halon stands. The turn runs in ConversationReplyJob, and ask_halon and
    # get_halon_answer wait on it for a while within the request, holding no database connection between looks.
    module HalonAnswer
      STATUS_ANSWERED = "answered"
      STATUS_WAITING = "waiting"
      STATUS_WORKING = "working"
      # A wait holds a web thread, so it stays under the 25 seconds Puma lets a request finish on a deploy (config/puma.rb).
      WAIT = 20.seconds
      LOOK_EVERY = 1.second

      def self.after_waiting(conversation)
        (WAIT / LOOK_EVERY).to_i.times do
          break unless conversation.reload.answer_owed?

          let_go_of_the_database
          pause(LOOK_EVERY)
        end
        now(conversation.reload)
      end

      # A turn that gave up is an error with the sentence it left in the chat, such as an AI account out of credit.
      def self.now(conversation)
        return working(conversation) if conversation.answer_owed?
        return Mcp::ToolDispatcher.error_response(last_answer(conversation)) if conversation.reply_failed?

        asked = conversation.chat&.awaiting_decision.to_a
        return waiting(conversation, asked) if asked.any?

        response(status: STATUS_ANSWERED, answer: last_answer(conversation), conversation_id: conversation.id)
      end

      def self.response(payload)
        ::MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ], structured_content: payload)
      end

      def self.working(conversation)
        response(
          status: STATUS_WORKING, conversation_id: conversation.id,
          answer: "Halon is still working on this. Call #{GET_HALON_ANSWER} with this conversation_id to wait for the answer."
        )
      end

      # What the agent paused on, in the words the dashboard would show, so the caller can tell the person.
      def self.waiting(conversation, asked)
        questions = asked.map { |call| Chat::Tools.confirmation(call).question }
        response(
          status: STATUS_WAITING, conversation_id: conversation.id, waiting_on: questions,
          answer: "Halon needs a confirmation before it can go on: #{questions.to_sentence} " \
                  "Confirm it in Firefight, then ask again."
        )
      end

      # A turn that gave up says why in the chat, so the last thing Halon said is the answer or the reason.
      def self.last_answer(conversation)
        said = conversation.chat&.readable_messages&.where(role: Chat::Message::ROLE_ASSISTANT)&.last
        Chat::Chart::Marker.strip(said&.content).presence || Conversation::Delivery::FAILED
      end

      # The request only waits, so its connections go back to the pool until the next look. One inside a transaction stays.
      def self.let_go_of_the_database
        ActiveRecord::Base.connection_handler.connection_pool_list(:all).each do |pool|
          pool.release_connection unless pool.active_connection&.transaction_open?
        end
      end

      def self.pause(seconds) = sleep(seconds)

      private_class_method :now, :response, :working, :waiting, :last_answer
    end
  end
end
