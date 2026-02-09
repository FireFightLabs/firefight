# Handles the "Create an incident" global Slack shortcut
# Opens the incident creation modal
module Interactions
  class CreateIncidentShortcutHandler
    extend WorkspaceFinding

    def self.execute(payload)
      workspace = find_workspace(payload)
      trigger_id = payload["trigger_id"]

      modal = Slack::ModalBuilder.incident_creation_form

      Slack::Client.open_modal(
        workspace: workspace,
        trigger_id: trigger_id,
        view: modal
      )

      Rails.logger.info({
        event: "shortcut.create_incident",
        workspace_id: workspace.id,
        user_id: payload.dig("user", "id")
      })

      nil
    rescue Slack::Client::TriggerExpiredError
      Rails.logger.warn({
        event: "shortcut.trigger_expired",
        workspace_id: workspace&.id,
        trigger_id: trigger_id
      })

      {
        response_action: "errors",
        errors: { base: "This shortcut has expired. Please try again." }
      }
    end
  end
end
