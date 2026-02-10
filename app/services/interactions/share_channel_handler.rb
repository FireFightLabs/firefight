# Handles the "Share incidents channel" button click
# Opens a modal for the user to select channels/people to share with
module Interactions
  class ShareChannelHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      user_id = payload.dig("user", "id")
      trigger_id = payload["trigger_id"]

      adapter = Slack::WorkspaceAdapter.new(workspace)
      adapter.open_share_modal(
        trigger_id: trigger_id,
        user_id: user_id,
        channel_id: workspace.incidents_channel_id
      )

      Rails.logger.info({
        event: "interactions.share_modal_opened",
        message: "Opened share channel modal",
        workspace_id: workspace.id,
        user_id: user_id
      })

      { response_action: "clear" }
    rescue AdapterError::TriggerExpired
      Rails.logger.warn({
        event: "interactions.trigger_expired",
        message: "Trigger ID expired when opening share modal",
        workspace_id: workspace.id,
        user_id: user_id
      })

      {
        response_action: "errors",
        errors: { base: "This interaction has expired. Please try again." }
      }
    end
  end
end
