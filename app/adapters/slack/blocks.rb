module Slack
  # Slack's newer blocks (Blocks::Card, Blocks::Alert), each drawn rich or plain, and the small text helpers they and the
  # messages beside them share. Whether a workspace's Slack draws them is decided by WorkspaceAdapter#with_rich_blocks.
  module Blocks
    # Blocks that are only their elements, so one left with none is dropped rather than refused.
    HOLDERS = %w[actions context].freeze

    def self.mrkdwn(text) = { type: "mrkdwn", text: text }

    def self.section(text) = { type: "section", text: mrkdwn(text) }

    def self.context(text) = { type: "context", elements: [ mrkdwn(text) ] }

    # Slack refuses a whole message over one empty slot in a list, such as a button a builder left out as nil or false.
    # Every message passes through here on its way out, so no builder has to remember.
    def self.compact(blocks)
      return blocks unless blocks.is_a?(Array)

      blocks.filter_map { |block| without_empty_slots(block) if block }.reject { |block| empty_holder?(block) }
    end

    def self.without_empty_slots(value)
      case value
      when Array then value.filter_map { |item| without_empty_slots(item) if item }
      when Hash then value.transform_values { |item| without_empty_slots(item) }
      else value
      end
    end
    private_class_method :without_empty_slots

    def self.empty_holder?(block)
      return false unless block.is_a?(Hash)

      type = block[:type] || block["type"]
      elements = block[:elements] || block["elements"]
      HOLDERS.include?(type) && elements.is_a?(Array) && elements.empty?
    end
    private_class_method :empty_holder?
  end
end
