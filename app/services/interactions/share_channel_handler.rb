module Interactions
  class ShareChannelHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      workspace = interaction.workspace
      adapter = workspace.adapter

      adapter.open_share_modal(
        trigger_id: interaction.trigger_id,
        user_id: interaction.user_id,
        channel_id: workspace.incidents_channel_id
      )

      Rails.logger.info({
        event: "interactions.share_modal_opened",
        message: "Opened share channel modal",
        workspace_id: workspace.id,
        user_id: interaction.user_id
      })

      adapter.modal_close_response
    rescue AdapterError::TriggerExpired
      Rails.logger.warn({
        event: "interactions.trigger_expired",
        message: "Trigger ID expired when opening share modal",
        workspace_id: workspace.id,
        user_id: interaction.user_id
      })

      adapter.modal_errors_response({ base: "This interaction has expired. Please try again." })
    end
  end
end
