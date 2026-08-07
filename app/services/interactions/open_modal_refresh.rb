module Interactions
  # A control clicked inside a modal changes state the modal is already
  # showing, and Slack does not redraw it. Without this the row keeps its old
  # button and the click looks like it did nothing.
  #
  # Rebuilds from the same inputs the modal was opened with, so a refreshed
  # view is identical to a freshly opened one.
  module OpenModalRefresh
    def self.call(interaction, workspace)
      view = interaction.view
      return if view.blank?

      rebuilt = rebuild(view, workspace)
      return if rebuilt.nil?

      workspace.adapter.update_modal(view_id: view["id"], view: rebuilt)
    rescue ActiveRecord::RecordNotFound, Slack::PrivateMetadata::InvalidError, AdapterError => e
      Rails.logger.warn({ event: "interactions.modal_refresh_failed", error: e.message })
      nil
    end

    def self.rebuild(view, workspace)
      metadata = Slack::PrivateMetadata.parse(view["private_metadata"])

      case view["callback_id"]
      when Identifiers::INCIDENT_ACTIONS_MODAL
        Slack::Modals::ActionItemsList.build(incident(workspace, metadata), kind: :action)
      when Identifiers::INCIDENT_FOLLOWUPS_MODAL
        Slack::Modals::ActionItemsList.build(incident(workspace, metadata), kind: :followup)
      when Identifiers::RUNBOOK_DETAIL_MODAL
        Slack::Modals::RunbookDetail.build(workspace.incident_runbooks.find(metadata.incident_runbook_id))
      end
    end

    def self.incident(workspace, metadata)
      workspace.incidents.find(metadata.incident_id)
    end
  end
end
