module Slack::WorkspaceAdapter::IncidentModals
  extend ActiveSupport::Concern

  def update_modal(view_id:, view:)
    translate_errors do
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  # Refreshes the open incident-creation modal with new dispatch context
  # (severity / type selected via dispatch_action) without losing other
  # user-entered values.
  def update_incident_creation_modal(view_id:, state: {})
    translate_errors do
      view = Slack::Modals::IncidentCreation.build(workspace: @workspace, state: state)
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  # Patches the home modal's help section based on the selected command,
  # preserving everything else about the open view.
  def update_home_modal(view:, selected_command:)
    translate_errors do
      help_text = Slack::Modals::Home.command_help(selected_command)
      updated_blocks = view["blocks"].map do |block|
        if block["block_id"] == "command_details_block"
          block.merge("text" => { "type" => "mrkdwn", "text" => help_text })
        else
          block
        end
      end

      Slack::Client.update_modal(
        workspace: @workspace,
        view_id: view["id"],
        view: {
          type: "modal",
          callback_id: Identifiers::INCIDENT_HOME_MODAL,
          private_metadata: view["private_metadata"],
          title: view["title"],
          submit: view["submit"],
          close: view["close"],
          blocks: updated_blocks
        }
      )

      { success: true }
    end
  end

  # Push-vs-open dispatch: open as a top-level modal when invoked directly,
  # or push onto an existing stack when invoked from another modal (e.g.
  # the actions list).
  def open_create_action_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::Modals::ActionItemsForm.build(incident, kind: :action, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def open_create_followup_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::Modals::ActionItemsForm.build(incident, kind: :followup, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  # Skip opening the link modal when there's nothing in the workspace to
  # link to — the build returns nil in that case.
  def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil, default_type: IncidentRelationship::RELATED)
    view = Slack::Modals::Link.build(incident, private_metadata: private_metadata, default_type: default_type)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end
end
