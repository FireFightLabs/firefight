module Interactions
  # The callback_id is the only thing the action and follow-up modals differ on.
  class CreateActionItemHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      kind = Identifiers::ACTION_ITEMS_FORM_KINDS[interaction.callback_id]

      description = interaction.values.dig(Identifiers::ACTION_ITEM_DESCRIPTION_BLOCK, Identifiers::ACTION_ITEM_DESCRIPTION_INPUT, "value")
      assignee_user_id = interaction.values.dig(Identifiers::ACTION_ITEM_ASSIGNEE_BLOCK, Identifiers::ACTION_ITEM_ASSIGNEE_SELECT, "selected_user")
      if assignee_user_id
        assignee = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: assignee_user_id,
          adapter: workspace.adapter
        )
        return workspace.adapter.modal_errors_response({ Identifiers::ACTION_ITEM_ASSIGNEE_BLOCK => "Couldn't load that user's profile from Slack. Please try again in a moment." }) unless assignee
      end

      platform_data = {}
      platform_data[:source_message_link] = metadata.source_message_link if metadata.source_message_link

      IncidentActionService.new(workspace).create_action(
        incident: incident,
        created_by: member,
        action_type: IncidentAction::ACTION_TYPE_BY_KIND.fetch(kind),
        description: description,
        assignee: assignee,
        platform_data: platform_data
      )
      Interactions::ModalCleanup.dismiss_prompt(workspace, metadata)

      workspace.adapter.modal_close_response
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.create_action_item.record_not_found", kind: kind, error: e.message })
      workspace.adapter.modal_errors_response({ Identifiers::ACTION_ITEM_DESCRIPTION_BLOCK => Interactions::ModalCleanup::RECORD_GONE })
    end
  end
end
