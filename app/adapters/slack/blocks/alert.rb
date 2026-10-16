module Slack
  module Blocks
    # One line saying how something ended or changed, coloured by how it went.
    #
    #   alert = Slack::Blocks::Alert.new(level: Slack::Blocks::Alert::SUCCESS, text: "Resolved by <@U1> after 1h 12m",
    #                                    emoji: Slack::Emoji::RESOLVED)
    #   alert.to_blocks(rich: true)  # one alert block
    #   alert.to_blocks(rich: false) # the house title, a bold section opening with the emoji
    #
    # text is mrkdwn the caller has already escaped, and emoji a shortcode from Slack::Emoji. A text past Slack's limit is
    # never cut, it is drawn plain.
    class Alert
      DEFAULT = "default".freeze
      INFO = "info".freeze
      WARNING = "warning".freeze
      ERROR = "error".freeze
      SUCCESS = "success".freeze
      LEVELS = [ DEFAULT, INFO, WARNING, ERROR, SUCCESS ].freeze
      TEXT_LIMIT = 200

      attr_reader :level, :text, :emoji

      def initialize(level:, text:, emoji: nil)
        raise ArgumentError, "Unknown alert level #{level.inspect}" unless LEVELS.include?(level)

        @level = level
        @text = text.to_s
        @emoji = emoji
      end

      def to_blocks(rich:)
        shown = emoji ? "#{emoji} #{text}" : text
        return [ { type: "alert", level: level, text: Blocks.mrkdwn(shown) } ] if rich && shown.length <= TEXT_LIMIT

        [ Blocks.section(emoji ? "#{emoji}  *#{text}*" : "*#{text}*") ]
      end
    end
  end
end
