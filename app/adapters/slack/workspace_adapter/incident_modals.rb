module Slack::WorkspaceAdapter::IncidentModals
  extend ActiveSupport::Concern

  def build_incident_creation_view(selected_severity_slug: nil, selected_type_id: nil)
    Slack::Modals::IncidentCreation.build(workspace: @workspace, selected_severity_slug: selected_severity_slug, selected_type_id: selected_type_id)
  end

  def build_incident_created_view(incident)
    Slack::Modals::IncidentCreated.build(incident, team_id: @workspace.platform_id)
  end

  def open_incident_creation_modal(trigger_id:)
    open_modal(trigger_id: trigger_id, view: build_incident_creation_view)
  end

  def update_incident_creation_modal(view_id:, selected_severity_slug: nil, selected_type_id: nil)
    translate_errors do
      updated_view = build_incident_creation_view(selected_severity_slug: selected_severity_slug, selected_type_id: selected_type_id)

      Slack::Client.update_modal(
        workspace: @workspace,
        view_id: view_id,
        view: updated_view
      )

      { success: true }
    end
  end

  def open_home_modal(trigger_id:, channel_id:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::Modals::Home.build(channel_id: channel_id)
    )
  end

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

  def build_summary_view(incident, private_metadata: nil)
    Slack::Modals::Summary.build(incident, private_metadata: private_metadata)
  end

  def open_summary_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_summary_view(incident, private_metadata: private_metadata))
  end

  def build_lead_view(incident)
    Slack::Modals::Lead.build(incident)
  end

  def open_lead_modal(trigger_id:, incident:)
    open_modal(trigger_id: trigger_id, view: build_lead_view(incident))
  end

  def build_incident_update_view(incident, private_metadata: nil)
    Slack::Modals::IncidentUpdate.build(incident, private_metadata: private_metadata)
  end

  def open_incident_update_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_incident_update_view(incident, private_metadata: private_metadata))
  end

  def build_actions_list_view(incident)
    Slack::Modals::ActionItemsList.build(incident, kind: :action)
  end

  def open_actions_list_modal(trigger_id:, incident:)
    open_modal(trigger_id: trigger_id, view: build_actions_list_view(incident))
  end

  def open_followups_list_modal(trigger_id:, incident:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::Modals::ActionItemsList.build(incident, kind: :followup)
    )
  end

  def open_create_action_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::Modals::ActionItemsForm.build(incident, kind: :action, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def open_create_followup_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::Modals::ActionItemsForm.build(incident, kind: :followup, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def build_close_view(incident, private_metadata: nil)
    Slack::Modals::IncidentClose.build(incident, private_metadata: private_metadata)
  end

  def open_close_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_close_view(incident, private_metadata: private_metadata))
  end

  def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil, default_type: IncidentRelationship::RELATED)
    view = Slack::Modals::Link.build(incident, private_metadata: private_metadata, default_type: default_type)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end

  def open_reopen_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::Modals::Reopen.build(incident, private_metadata: private_metadata)
    )
  end

  def build_escalate_view(incident, private_metadata: nil)
    Slack::Modals::Escalate.build(incident, private_metadata: private_metadata)
  end

  def open_escalate_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_escalate_view(incident, private_metadata: private_metadata))
  end

  def build_invite_view(incident, selected_user_ids: [], private_metadata: nil)
    Slack::Modals::Invite.build(incident, selected_user_ids: selected_user_ids, private_metadata: private_metadata)
  end

  def open_invite_responders_modal(trigger_id:, incident:, selected_user_ids: [], private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_invite_view(incident, selected_user_ids: selected_user_ids, private_metadata: private_metadata))
  end

  def open_shoutout_modal(trigger_id:, incident:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::Modals::Shoutout.build(incident)
    )
  end
end
