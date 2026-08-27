module Interactions
  # A control clicked inside a modal changes state the modal is already
  # showing, and Slack does not redraw it. Without this the row keeps its old
  # button and the click looks like it did nothing.
  #
  # Rebuilds from the same inputs the modal was opened with, so a refreshed
  # view is identical to a freshly opened one.
  module OpenModalRefresh
    def self.call(interaction, workspace)
      return if interaction.view_id.blank?

      rebuilt = rebuild(interaction, workspace)
      return if rebuilt.nil?

      workspace.adapter.update_modal(view_id: interaction.view_id, view: rebuilt)
    rescue ActiveRecord::RecordNotFound, AdapterError => e
      Rails.logger.warn({ event: "interactions.modal_refresh_failed", error: e.message })
      nil
    end

    def self.rebuild(interaction, workspace)
      metadata = interaction.metadata

      if interaction.callback_id == Identifiers::RUNBOOK_DETAIL_MODAL
        return workspace.adapter.build_modal(PlatformAdapter::Modal::RUNBOOK_DETAIL, workspace.incident_runbooks.find(metadata.incident_runbook_id))
      end

      kind = Identifiers::ACTION_ITEMS_LIST_KINDS[interaction.callback_id]
      return nil if kind.nil?

      workspace.adapter.build_modal(PlatformAdapter::Modal::ACTION_ITEMS_LIST, workspace.incidents.find(metadata.incident_id), kind: kind)
    end
  end
end
