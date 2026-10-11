module FirefightAi
  # What Halon's reply says its next step would be, which the reply carries as a last line in a fixed shape the app takes
  # off before anyone sees it. A reply that ends by offering a read Halon could take itself is sent back once to take it
  # (AgentLoop), since the person wants the answer, not an offer to look. A change, a choice that is the person's or a
  # question only they can answer ends the turn as before. Reading the shape costs nothing, where judging the words
  # would cost a model call.
  module NextStep
    READ = "read".freeze
    CHANGE = "change".freeze
    CHOICE = "choice".freeze
    NONE = "none".freeze
    KINDS = [ READ, CHANGE, CHOICE, NONE ].freeze

    LINE = /\s*\[next step: (#{KINDS.join('|')})\]\s*\z/i
    ANYWHERE = /\s*\[next step: (?:#{KINDS.join('|')})\]/i
    OPENING = "[next step: ".freeze

    RULE = "End every reply with a last line saying what your next step would be, which Firefight takes off before anyone " \
           "sees it: [next step: read] when it is a read you could take yourself, [next step: change] when it is a change, " \
           "[next step: choice] when it is the person's choice or a question only they can answer, and [next step: none] " \
           "when nothing is next.".freeze
    SEND_BACK = "Your reply offered a read you can take yourself. Take it now, then answer with what it showed.".freeze

    def self.kind(text) = text.to_s.match(LINE)&.[](1)&.downcase

    def self.without(text) = text.to_s.gsub(ANYWHERE, "").rstrip

    # Text as it streams, with the line held back while it may still be arriving and dropped once whole, so a person
    # never sees it. finish hands over what was held when it turned out to be something else.
    class Stream
      def initialize(&emit)
        @emit = emit
        @held = +""
      end

      def add(text)
        @held << text.to_s
        @held = @held.gsub(ANYWHERE, "")
        cut = @held.rindex("[")
        cut -= 1 while cut&.positive? && @held[cut - 1].match?(/\s/)
        kept = cut && arriving?(@held[cut..].lstrip) ? @held.slice!(cut..) : +""
        shown = @held
        @held = kept
        @emit.call(shown) unless shown.empty?
      end

      def finish
        shown = @held.sub(ANYWHERE, "")
        @held = +""
        @emit.call(shown) unless shown.empty?
      end

      private

      def arriving?(fragment)
        lowered = fragment.downcase
        OPENING.start_with?(lowered) || (lowered.start_with?(OPENING) && KINDS.any? { |kind| "#{kind}]".start_with?(lowered.delete_prefix(OPENING)) })
      end
    end
  end
end
