module FirefightAi
  class AgentLoop
    # Decides when a chat has to make room, and asks the chat's own record to do it. Clearing old
    # tool results comes first, since it needs no model call. The chat is rebuilt only when that was not enough.
    class Room
      CLEAR_AT = 0.50
      REBUILD_AT = 0.75
      CHARACTERS_PER_TOKEN = 4

      HANDOVER = "Your working messages are about to be put away to make room. Write a note to yourself. Say what you " \
                 "have established, what you have ruled out, and what you were about to check and why. Plain text only.".freeze

      # memory is the saved chat, which knows its model's window and how to clear and rebuild itself.
      def initialize(chat, memory)
        @chat = chat
        @memory = memory
        @read_at_last_reply = nil
      end

      def saw(reply)
        tokens = reply.tokens
        @read_at_last_reply = [ tokens&.input, tokens&.cache_read, tokens&.cache_write, tokens&.output ].sum(&:to_i)
      end

      # Called before a turn. The block writes the agent's note to itself and returns it.
      def make
        return unless @memory

        clear if in_use >= window * CLEAR_AT
        rebuild(yield) if in_use >= window * REBUILD_AT
      end

      # The provider refused the chat as too long, so the model cannot be asked for a note.
      def make_after_refusal = rebuild(nil)

      def possible? = !@memory.nil?

      private

      def window = @memory.context_window!

      def clear
        freed = @memory.clear_old_results!(tokens_before: in_use)
        settle if freed.positive?
      end

      def rebuild(note)
        @memory.rebuild!(note: note, tokens_before: in_use)
        settle
      end

      # The chat changed underneath, so the provider's last count no longer describes it.
      def settle
        @chat.reload
        @read_at_last_reply = nil
      end

      # The provider's own count from the last reply, plus an estimate for what has arrived since and it has not seen.
      def in_use
        return characters(messages) / CHARACTERS_PER_TOKEN if @read_at_last_reply.nil?

        @read_at_last_reply + (characters(since_last_reply) / CHARACTERS_PER_TOKEN)
      end

      def since_last_reply
        last = messages.rindex { |message| message.role == :assistant }
        last ? messages[(last + 1)..] : messages
      end

      def characters(list) = list.sum { |message| message.content.to_s.length }

      def messages = @chat.to_llm.messages
    end
  end
end
