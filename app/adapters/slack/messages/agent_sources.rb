module Slack
  module Messages
    # What Halon read to give an answer, as one small grey line under it, so a thread gets one compact block and never a
    # message per source. Each read links to its page when its result gave one.
    module AgentSources
      SHOWN = 8
      SEPARATOR = " · ".freeze

      # sources are Chat::Sources::Source, each with a title and a url or nil.
      def self.build(sources)
        return [] if sources.empty?

        listed = sources.first(SHOWN).map { |source| shown(source) }
        more = sources.size - SHOWN
        text = "Read: #{listed.join(SEPARATOR)}#{" and #{more} more" if more.positive?}"
        [ { type: "context", elements: [ { type: "mrkdwn", text: text.truncate(Formatting::SECTION_TEXT_LIMIT) } ] } ]
      end

      def self.shown(source)
        title = Slack::Mrkdwn.escape(source.title.to_s.squish.truncate(80))
        source.url.present? ? "<#{source.url.delete('<>|')}|#{title}>" : title
      end
    end
  end
end
