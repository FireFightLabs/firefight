module Slack
  class InteractionParser < ::InteractionParser
    def self.parse(payload)
      payload = payload.with_indifferent_access
      Interaction.new(
        platform: Platforms::SLACK,
        type: payload[:type],
        team_id: payload.dig(:team, :id) || payload.dig(:user, :team_id),
        user_id: payload.dig(:user, :id),
        trigger_id: payload[:trigger_id],
        channel_id: payload.dig(:channel, :id),
        action_id: payload.dig(:actions, 0, :action_id),
        callback_id: payload.dig(:view, :callback_id) || payload[:callback_id],
        selected_value: payload.dig(:actions, 0, :selected_option, :value),
        selected_user: payload.dig(:actions, 0, :selected_user),
        action_value: payload.dig(:actions, 0, :value),
        block_id: payload.dig(:actions, 0, :block_id),
        private_metadata: payload.dig(:view, :private_metadata),
        view: payload[:view],
        values: payload.dig(:view, :state, :values),
        raw: payload
      )
    end
  end
end
