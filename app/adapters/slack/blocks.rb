module Slack
  # Slack's newer blocks, which not every workspace's Slack draws yet. Each builder here draws itself rich or plain
  # (to_blocks(rich:)), and the adapter decides which per workspace and per kind (WorkspaceAdapter::RichBlocks), so a
  # message is never lost to how it looks.
  module Blocks
    PLAN = "plan".freeze
    CARD = "card".freeze
    ALERT = "alert".freeze
    KINDS = [ PLAN, CARD, ALERT ].freeze

    def self.mrkdwn(text) = { type: "mrkdwn", text: text }

    def self.section(text) = { type: "section", text: mrkdwn(text) }

    def self.context(text) = { type: "context", elements: [ mrkdwn(text) ] }
  end
end
