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
        return adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CREATION))
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

      incident_metadata = ModalState.encode(incident_id: incident.id, channel_id: channel_id)

      case selected
      when Identifiers::HOME_ACTION_STATUS, Identifiers::HOME_ACTION_SEVERITY
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::INCIDENT_UPDATE, incident, metadata: incident_metadata))
      when Identifiers::HOME_ACTION_SUMMARY
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::SUMMARY, incident, metadata: incident_metadata))
      when Identifiers::HOME_ACTION_ESCALATE
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::ESCALATE, incident, metadata: incident_metadata))
      when Identifiers::HOME_ACTION_INVITE
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::INVITE, incident, metadata: incident_metadata))
      when Identifiers::HOME_ACTION_LEAD
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::LEAD, incident))
      when Identifiers::HOME_ACTION_ROLES
        roles = workspace.incident_roles.active.ordered
        if roles.empty?
          return { response_action: "errors", errors: { "action_select_block" => "No incident roles are set up yet. Add them in Settings." } }
        end

        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::ROLES, incident, roles))
      when Identifiers::HOME_ACTION_ACTIONS
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::ACTION_ITEMS_LIST, incident, kind: :action))
      when Identifiers::HOME_ACTION_RUNBOOK
        available = incident.attachable_runbooks
        if available.empty?
          return { response_action: "errors", errors: { "action_select_block" => "No runbooks left to attach. Add them in Settings." } }
        end

        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::ATTACH_RUNBOOK, incident, available))
      when Identifiers::HOME_ACTION_CLOSE
        adapter.form_update_response(adapter.build_modal(PlatformAdapter::Modal::INCIDENT_CLOSE, incident, metadata: incident_metadata))
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
      PostmortemGenerationJob.perform_later(incident.id) if member
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
