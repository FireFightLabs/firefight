module Slack
  module BlockValueExtractor
    def self.extract(values, block_id:, action_id:, field_type:)
      block_values = values.dig(block_id, action_id)
      return nil unless block_values

      # A users_select element reports under "selected_user" whatever the
      # registered field_type says.
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
