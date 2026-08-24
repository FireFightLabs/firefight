module Interactions
  # The action and follow-up modals submit here. The callback_id names the
  # kind, and that is the only thing the two kinds ever differed on.
  class CreateActionItemHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      kind = Slack::Modals::ActionItemsForm.kind_for(interaction.callback_id)

      description = interaction.values.dig("description_block", "description_input", "value")
      assignee_user_id = interaction.values.dig("assignee_block", "assignee_select", "selected_user")
      if assignee_user_id
        assignee = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: workspace,
          platform_user_id: assignee_user_id,
          adapter: workspace.adapter
        )
        return { response_action: "errors", errors: { "assignee_block" => "Couldn't load that user's profile from Slack. Please try again in a moment." } } unless assignee
      end

      platform_data = {}
      platform_data[:source_message_link] = metadata.source_message_link if metadata.source_message_link

      IncidentActionService.new(workspace).create_action(
        incident: incident,
        created_by: member,
        action_type: Slack::Modals::ActionItemsForm::ACTION_TYPES.fetch(kind),
        description: description,
        assignee: assignee,
        platform_data: platform_data
      )

      { response_action: "clear" }
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn({ event: "interactions.create_action_item.record_not_found", kind: kind, error: e.message })
      { response_action: "errors", errors: { "description_block" => "Something went wrong. Please close this modal and try again." } }
    end
  end
end
