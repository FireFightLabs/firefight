module Slack
  module Modals
    # The call an approval rule held, as the tool is given it, which its message keeps off it. Everything here came from
    # the model or other systems, so it is escaped.
    module HeldCallDetails
      def self.build(held_call)
        call = [ held_call.call, held_call.target ].compact.map { |part| Mrkdwn.escape(part) }.join(" on ")
        given = held_call.asked.map { |name, value| "#{Mrkdwn.escape(name)}: #{Messages::Formatting.local_moments(Mrkdwn.escape(value))}" }
        texts = [ "*#{Mrkdwn.escape(held_call.headline)}*", "*The call*\n#{call}", ("*What it was given*\n#{given.join("\n")}" if given.any?) ].compact
        {
          type: "modal", title: { type: "plain_text", text: "Details" }, close: { type: "plain_text", text: "Close" },
          blocks: texts.map { |text| { type: "section", text: { type: "mrkdwn", text: text.truncate(Messages::Formatting::SECTION_TEXT_LIMIT) } } }
        }
      end
    end
  end
end
