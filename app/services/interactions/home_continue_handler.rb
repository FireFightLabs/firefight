module Interactions
  class HomeContinueHandler
    def self.execute(interaction)
      selected = interaction.values.dig(
        "action_select_block",
        Identifiers::HOME_ACTION_SELECT,
        "selected_option",
        "value"
      )
      return nil if selected.blank?

      metadata   = JSON.parse(interaction.private_metadata)
      channel_id = metadata["channel_id"]
      workspace  = interaction.workspace
      adapter    = WorkspaceAdapter.for(workspace)

      if selected == Identifiers::HOME_ACTION_NEW
        return { response_action: "push", view: adapter.build_incident_creation_view }
      end

      if selected == Identifiers::HOME_ACTION_LIST
        post_list(workspace, adapter, channel_id, interaction.user_id)
        return { response_action: "clear" }
      end

      incident = workspace.incidents.active.in_channel(channel_id).first
      unless incident
        return { response_action: "errors", errors: { "action_select_block" => "No active incident found in this channel." } }
      end

      incident_metadata = { incident_id: incident.id, channel_id: channel_id }.to_json

      case selected
      when Identifiers::HOME_ACTION_STATUS, Identifiers::HOME_ACTION_SEVERITY
        { response_action: "push", view: adapter.build_incident_update_view(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_SUMMARY
        { response_action: "push", view: adapter.build_summary_view(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_ESCALATE
        { response_action: "push", view: adapter.build_escalate_view(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_INVITE
        { response_action: "push", view: adapter.build_invite_view(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_LEAD
        { response_action: "push", view: adapter.build_lead_view(incident) }
      when Identifiers::HOME_ACTION_ACTIONS
        { response_action: "push", view: adapter.build_actions_list_view(incident) }
      when Identifiers::HOME_ACTION_CLOSE
        { response_action: "push", view: adapter.build_close_view(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_TIMELINE
        post_timeline(adapter, incident, channel_id, interaction.user_id)
        { response_action: "clear" }
      when Identifiers::HOME_ACTION_POSTMORTEM
        { response_action: "errors", errors: { "action_select_block" => "Postmortem generation is not yet available." } }
      end
    rescue JSON::ParserError, ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.home_continue.error", error: e.message })
      nil
    end

    def self.post_timeline(adapter, incident, channel_id, user_id)
      response = Commands::Firefight::TimelineHandler.build_response(incident)
      adapter.post_ephemeral(
        channel_id: channel_id,
        user_id: user_id,
        text: response[:text],
        blocks: response[:blocks]
      )
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.home_continue.post_timeline_failed", error: e.message })
    end
    private_class_method :post_timeline

    def self.post_list(workspace, adapter, channel_id, user_id)
      response = Commands::Firefight::ListHandler.build_response(workspace)
      adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: response[:text])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.home_continue.post_list_failed", error: e.message })
    end
    private_class_method :post_list
  end
end
