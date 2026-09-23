module Mcp
  module Tools
    # Connecting happens in the connect dialog, where OAuth and keys belong, so this only says what exists and
    # where each stands. In the dashboard chat a category's answer is drawn as a table with a Connect button per row.
    class ListIntegrations < Base
      tool_name LIST_INTEGRATIONS
      authorize_as Ability::Action::RESOURCE_INTEGRATIONS
      description "What can be connected to Firefight and what already is, by category. Without a category, " \
                  "one line per category saying what is connected in it, so you can ask the person which they want. " \
                  "With a category, every provider in it and where it stands. The person is shown that as a table " \
                  "they connect from, so do not list the providers again in your reply. Connecting happens there, " \
                  "never in the chat: never ask for or accept a key, token or password. Docs: #{Docs::MCP_SERVER}"
      annotations(**READ_ONLY)
      choice :category, from: ->(_workspace) { IntegrationProvider.category_list }
      input_schema(
        properties: {
          category: { type: "string", description: "The category to show. Leave it out for the overview" }
        }
      )

      def self.perform(workspace:, args:)
        return respond(categories: IntegrationProvider.cards_for(workspace).map { |card| overview(card) }) if args[:category].blank?

        card = IntegrationProvider.card_for(workspace, IntegrationProvider.category_for!(args[:category]))
        respond(
          category: card.category.slug, name: card.category.name, about: card.category.tagline,
          providers: card.rows.map { |row| row_payload(row) }
        )
      end

      def self.overview(card)
        connected = card.rows.reject { |row| row.state == IntegrationProvider::STATE_NOT_CONNECTED }
        {
          category: card.category.slug, name: card.category.name, about: card.category.tagline,
          connected: connected.map { |row| row.provider.name }, available: card.rows.size
        }
      end

      def self.row_payload(row)
        { key: row.provider.key, name: row.provider.name, about: row.provider.description, state: row.state, connections: row.connections }
      end
    end
  end
end
