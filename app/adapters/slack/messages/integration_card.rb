module Slack
  module Messages
    # A category of integrations as a list, one line per provider. Connecting needs the dashboard, where OAuth
    # and keys belong, so each button opens that provider's connect dialog there.
    module IntegrationCard
      STATE_LABELS = {
        IntegrationProvider::STATE_CONNECTED => "Connected",
        IntegrationProvider::STATE_NEEDS_ATTENTION => "Needs attention",
        IntegrationProvider::STATE_TURNED_OFF => "Turned off",
        IntegrationProvider::STATE_NOT_CONNECTED => "Not connected"
      }.freeze
      ACTION_LABELS = {
        IntegrationProvider::STATE_NEEDS_ATTENTION => "Reconnect",
        IntegrationProvider::STATE_NOT_CONNECTED => "Connect"
      }.freeze

      def self.build(card)
        [
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(card.category.name)}*\n#{Mrkdwn.escape(card.category.tagline)}" } },
          *card.rows.map { |row| row_block(row) }
        ]
      end

      def self.fallback(card) = "#{card.category.name} integrations"

      def self.row_block(row)
        text = "*#{Mrkdwn.escape(row.provider.name)}*  ·  #{STATE_LABELS.fetch(row.state)}\n#{Mrkdwn.escape(row.provider.description)}"
        block = { type: "section", text: { type: "mrkdwn", text: text } }
        action = ACTION_LABELS[row.state]
        url = action && DashboardUrl.connect_integration(row.provider.key)
        return block unless url

        block.merge(accessory: { type: "button", text: { type: "plain_text", text: action }, url: url })
      end
      private_class_method :row_block
    end
  end
end
