module Slack
  # Slack's newer blocks (Blocks::Card, Blocks::Alert), each drawn rich or plain, and the small text helpers they and the
  # messages beside them share. Whether a workspace's Slack draws them is decided by WorkspaceAdapter#with_rich_blocks.
  module Blocks
    def self.mrkdwn(text) = { type: "mrkdwn", text: text }

    def self.section(text) = { type: "section", text: mrkdwn(text) }

    def self.context(text) = { type: "context", elements: [ mrkdwn(text) ] }
  end
end
