module Slack
  module Blocks
    # How something stands, in one line marked by its level, such as a fix that was applied or a step that failed. Slack
    # draws its alert block only in modals and refuses it in a message, so a message always gets the line as a section
    # led by the level's emoji, and modal: true asks for the alert block where the workspace shows the newer blocks.
    # text is mrkdwn the caller already escaped.
    class Alert
      LEVEL_DEFAULT = "default".freeze
      LEVEL_INFO = "info".freeze
      LEVEL_WARNING = "warning".freeze
      LEVEL_ERROR = "error".freeze
      LEVEL_SUCCESS = "success".freeze
      LEVELS = [ LEVEL_DEFAULT, LEVEL_INFO, LEVEL_WARNING, LEVEL_ERROR, LEVEL_SUCCESS ].freeze
      EMOJI = { LEVEL_INFO => ":information_source:", LEVEL_WARNING => ":warning:", LEVEL_ERROR => ":x:", LEVEL_SUCCESS => ":white_check_mark:" }.freeze
      TEXT_LIMIT = 200

      attr_reader :level, :text

      def initialize(level:, text:)
        raise ArgumentError, "An alert's level is one of #{LEVELS.join(', ')}." unless LEVELS.include?(level)

        @level = level
        @text = text
      end

      def to_blocks(rich:, modal: false)
        return [ { type: "alert", level: level, text: { type: "mrkdwn", text: text.to_s.truncate(TEXT_LIMIT) } } ] if rich && modal

        [ { type: "section", text: { type: "mrkdwn", text: [ EMOJI[level], text ].compact.join("  ").truncate(Slack::Messages::Formatting::SECTION_TEXT_LIMIT) } } ]
      end
    end
  end
end
