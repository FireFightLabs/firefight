module Interactions
  # Publish on a member's request to publish a workflow, in an admin's direct messages. Publishing grants the workflow's
  # own identity what its steps need, so whoever pressed it must be able to grant, which the gateway checks, and it goes
  # through the same publishing as the workflow's page.
  class WorkflowPublishRequestHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_CREATE

    def self.execute(interaction)
      workspace = interaction.workspace
      request = Workflow::PublishRequest.where(workspace: workspace).find(interaction.action_value)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)

      result = WorkflowPublishService.new(request.workflow).publish_requested!(request, by: member)
      workspace.adapter.post_ephemeral(channel_id: interaction.channel_id, user_id: interaction.user_id, text: result.words) unless result.ok
      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
