module Slack
  module Messages
    # A category of integrations as a list, one line per provider. Connecting needs the dashboard, where OAuth
    # and keys belong, so each button opens that provider's connect dialog there.
    module IntegrationCard
      def self.build(card)
        [
          { type: "section", text: { type: "mrkdwn", text: "*#{Mrkdwn.escape(card.category.name)}*\n#{Mrkdwn.escape(card.category.tagline)}" } },
          *card.rows.map { |row| row_block(row) }
        ]
      end

      def self.fallback(card) = "#{card.category.name} integrations"

      def self.row_block(row)
        text = "*#{Mrkdwn.escape(row.provider.name)}*  ·  #{row.state_label}\n#{Mrkdwn.escape(row.provider.description)}"
        text += "\n#{connection_links(row)}" if row.connections.any?
        block = { type: "section", text: { type: "mrkdwn", text: text } }
        url = row.opens_connect? && DashboardUrl.connect_integration(row.provider.key)
        return block unless url

        block.merge(accessory: { type: "button", text: { type: "plain_text", text: row.action_label }, url: url })
      end
      private_class_method :row_block

      # Each connection opens its own details, so a provider backing several accounts names each.
      def self.connection_links(row)
        row.connections.filter_map do |connection|
          url = DashboardUrl.integration_details(connection[:id])
          url && "<#{url}|#{Mrkdwn.escape(connection[:name])}>"
        end.join("  ·  ")
      end
      private_class_method :connection_links
    end
  end
end
