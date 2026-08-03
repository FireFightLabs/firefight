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
    def self.extract(values, block_id:, action_id:, field_type:)
      block_values = values.dig(block_id, action_id)
      return nil unless block_values

      # users_select fields (e.g. the lead picker) put the selection under
      # "selected_user" regardless of the registered field_type — they're
      # rendered as Block Kit `users_select` elements.
      return block_values["selected_user"] if block_values.key?("selected_user")

      return block_values["value"] unless IncidentFieldDefinition.selectable?(field_type)

      if IncidentFieldDefinition.multi_valued?(field_type)
        block_values["selected_options"]&.map { |option| option["value"] }
      else
        block_values.dig("selected_option", "value")
      end
    end
  end
end
