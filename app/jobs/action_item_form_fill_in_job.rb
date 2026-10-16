# Fills in an action or follow-up form a reaction opened with the message it was added to. The form opens on the
# trigger and the platform is answered at once, so reading the message, however slow, never delays either.
class ActionItemFormFillInJob < ApplicationJob
  queue_as :default

  def perform(workspace_id, incident_id, kind, view_id, private_metadata)
    workspace = Workspace.find_by(id: workspace_id)
    incident = workspace&.incidents&.find_by(id: incident_id)
    return unless incident

    workspace.adapter.fill_in_action_item_modal(view_id: view_id, kind: kind.to_sym, incident: incident, private_metadata: private_metadata)
  end
end
