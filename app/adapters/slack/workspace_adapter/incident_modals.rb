module Slack::WorkspaceAdapter::IncidentModals
  extend ActiveSupport::Concern

  def build_incident_creation_view(selected_severity_slug: nil, selected_type_id: nil)
    Slack::ModalBuilder.incident_creation_form(workspace: @workspace, selected_severity_slug: selected_severity_slug, selected_type_id: selected_type_id)
  end

  def build_incident_created_view(incident)
    Slack::ModalBuilder.incident_created_confirmation(incident, team_id: @workspace.platform_id)
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
      view: Slack::ModalBuilder.home_modal(channel_id: channel_id)
    )
  end

  def update_home_modal(view:, selected_command:)
    translate_errors do
      help_text = Slack::ModalBuilder.home_command_help(selected_command)

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
    Slack::ModalBuilder.summary_modal(incident, private_metadata: private_metadata)
  end

  def open_summary_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_summary_view(incident, private_metadata: private_metadata))
  end

  def build_lead_view(incident)
    Slack::ModalBuilder.lead_modal(incident)
  end

  def open_lead_modal(trigger_id:, incident:)
    open_modal(trigger_id: trigger_id, view: build_lead_view(incident))
  end

  def build_incident_update_view(incident, private_metadata: nil)
    Slack::ModalBuilder.incident_update_modal(incident, private_metadata: private_metadata)
  end

  def open_incident_update_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_incident_update_view(incident, private_metadata: private_metadata))
  end

  def build_actions_list_view(incident)
    Slack::ModalBuilder.actions_list_modal(incident)
  end

  def open_actions_list_modal(trigger_id:, incident:)
    open_modal(trigger_id: trigger_id, view: build_actions_list_view(incident))
  end

  def open_followups_list_modal(trigger_id:, incident:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::ModalBuilder.followups_list_modal(incident)
    )
  end

  def open_create_action_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::ModalBuilder.create_action_modal(incident, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def open_create_followup_modal(trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::ModalBuilder.create_followup_modal(incident, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def build_close_view(incident, private_metadata: nil)
    Slack::ModalBuilder.close_modal(incident, private_metadata: private_metadata)
  end

  def open_close_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_close_view(incident, private_metadata: private_metadata))
  end

  def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil, default_type: IncidentRelationship::RELATED)
    view = Slack::ModalBuilder.link_incident_modal(incident, private_metadata: private_metadata, default_type: default_type)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end

  def open_reopen_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::ModalBuilder.reopen_modal(incident, private_metadata: private_metadata)
    )
  end

  def build_escalate_view(incident, private_metadata: nil)
    Slack::ModalBuilder.escalate_modal(incident, private_metadata: private_metadata)
  end

  def open_escalate_incident_modal(trigger_id:, incident:, private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_escalate_view(incident, private_metadata: private_metadata))
  end

  def build_invite_view(incident, selected_user_ids: [], private_metadata: nil)
    Slack::ModalBuilder.invite_responders_modal(
      incident,
      selected_user_ids: selected_user_ids,
      private_metadata: private_metadata
    )
  end

  def open_invite_responders_modal(trigger_id:, incident:, selected_user_ids: [], private_metadata: nil)
    open_modal(trigger_id: trigger_id, view: build_invite_view(incident, selected_user_ids: selected_user_ids, private_metadata: private_metadata))
  end

  def open_shoutout_modal(trigger_id:, incident:)
    open_modal(
      trigger_id: trigger_id,
      view: Slack::ModalBuilder.shoutout_modal(incident)
    )
  end
end
