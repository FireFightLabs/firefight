module Interactions
  class HomeContinueHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(interaction)
      selected = interaction.values.dig(
        "action_select_block",
        Identifiers::HOME_ACTION_SELECT,
        "selected_option",
        "value"
      )
      return nil if selected.blank?

      channel_id = interaction.metadata.channel_id
      workspace  = interaction.workspace
      adapter    = workspace.adapter

      if selected == Identifiers::HOME_ACTION_NEW
        return { response_action: "update", view: Slack::Modals::IncidentCreation.build(workspace: workspace) }
      end

      if selected == Identifiers::HOME_ACTION_LIST
        post_list(workspace, adapter, channel_id, interaction.user_id)
        return { response_action: "clear" }
      end

      if selected == Identifiers::HOME_ACTION_POSTMORTEM
        return handle_postmortem(workspace, channel_id, interaction.user_id)
      end

      incident = workspace.incidents.active.in_channel(channel_id).first
      unless incident
        return { response_action: "errors", errors: { "action_select_block" => "No active incident found in this channel." } }
      end

      incident_metadata = { incident_id: incident.id, channel_id: channel_id }.to_json

      case selected
      when Identifiers::HOME_ACTION_STATUS, Identifiers::HOME_ACTION_SEVERITY
        { response_action: "update", view: Slack::Modals::IncidentUpdate.build(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_SUMMARY
        { response_action: "update", view: Slack::Modals::Summary.build(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_ESCALATE
        { response_action: "update", view: Slack::Modals::Escalate.build(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_INVITE
        { response_action: "update", view: Slack::Modals::Invite.build(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_LEAD
        { response_action: "update", view: Slack::Modals::Lead.build(incident) }
      when Identifiers::HOME_ACTION_ROLES
        roles = workspace.incident_roles.active.ordered
        if roles.empty?
          return { response_action: "errors", errors: { "action_select_block" => "No incident roles are set up yet. Add them in Settings." } }
        end

        { response_action: "update", view: Slack::Modals::Roles.build(incident, roles) }
      when Identifiers::HOME_ACTION_ACTIONS
        { response_action: "update", view: Slack::Modals::ActionItemsList.build(incident, kind: :action) }
      when Identifiers::HOME_ACTION_RUNBOOK
        available = incident.attachable_runbooks
        if available.empty?
          return { response_action: "errors", errors: { "action_select_block" => "No runbooks left to attach. Add them in Settings." } }
        end

        { response_action: "update", view: Slack::Modals::AttachRunbook.build(incident, available) }
      when Identifiers::HOME_ACTION_CLOSE
        { response_action: "update", view: Slack::Modals::IncidentClose.build(incident, private_metadata: incident_metadata) }
      when Identifiers::HOME_ACTION_TIMELINE
        view = adapter.build_timeline_view(incident)
        return { response_action: "clear" } unless view
        { response_action: "push", view: view }
      end
    rescue JSON::ParserError, ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.home_continue.error", error: e.message })
      nil
    end

    def self.handle_postmortem(workspace, channel_id, user_id)
      incident = workspace.incidents.closed.in_channel(channel_id).first
      unless incident
        return { response_action: "errors", errors: { "action_select_block" => "No closed incident found in this channel." } }
      end

      if incident.postmortem.present?
        return { response_action: "errors", errors: { "action_select_block" => "A postmortem has already been generated for #{incident.identifier}." } }
      end

      unless defined?(FirefightAi)
        return { response_action: "errors", errors: { "action_select_block" => "AI features are not available." } }
      end

      gate = Entitlements.check(workspace, Entitlements::AI)
      if gate.blocked?
        return { response_action: "errors", errors: { "action_select_block" => gate.message } }
      end

      member = workspace.workspace_memberships.find_by(platform_user_id: user_id)
      FirefightAi::PostmortemGenerationJob.perform_later(incident.id, member.id) if member
      { response_action: "clear" }
    end
    private_class_method :handle_postmortem

    def self.post_list(workspace, adapter, channel_id, user_id)
      response = Commands::ListActiveIncidents.build_response(workspace)
      adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: response[:text])
    rescue AdapterError => e
      Rails.logger.warn({ event: "interactions.home_continue.post_list_failed", error: e.message })
    end
    private_class_method :post_list
  end
end
