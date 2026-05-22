module Slack
  # Extracts a typed value from a Slack `view.state.values` payload for a
  # single block/action pair. Encapsulates the Block Kit field-shape rules:
  #
  #   single_select / catalog_reference            → values[block][action]["selected_option"]["value"]
  #   multi_select  / catalog_multi_reference      → values[block][action]["selected_options"].map { _1["value"] }
  #   everything else (text, number, link, ...)    → values[block][action]["value"]
  #
  # Returns nil if the block/action isn't present in the submission.
  module BlockValueExtractor
    SINGLE_SELECT_TYPES = [
      IncidentFieldDefinition::TYPE_SINGLE_SELECT,
      IncidentFieldDefinition::TYPE_CATALOG_REFERENCE
    ].freeze

    MULTI_SELECT_TYPES = [
      IncidentFieldDefinition::TYPE_MULTI_SELECT,
      IncidentFieldDefinition::TYPE_CATALOG_MULTI_REFERENCE
    ].freeze

    def self.extract(values, block_id:, action_id:, field_type:)
      block_values = values.dig(block_id, action_id)
      return nil unless block_values

      case field_type
      when *SINGLE_SELECT_TYPES
        block_values.dig("selected_option", "value")
      when *MULTI_SELECT_TYPES
        block_values["selected_options"]&.map { |o| o["value"] }
      else
        block_values["value"]
      end
    end
  end
end
