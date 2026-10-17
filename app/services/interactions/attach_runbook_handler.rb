module Interactions
  class AttachRunbookHandler
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = interaction.metadata
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      slug = workspace.adapter.submitted_value(values: interaction.values, block_id: Identifiers::RUNBOOK_BLOCK, input_id: Identifiers::RUNBOOK_SELECT, kind: PlatformAdapter::Input::OPTION)

      RunbookAttachmentService.new(workspace).attach_by_slug(
        incident: incident, slug: slug, attached_by: member
      )

      workspace.adapter.modal_close_response
    rescue ActiveRecord::RecordNotFound
      workspace.adapter.modal_errors_response({ Identifiers::RUNBOOK_BLOCK => "That runbook is no longer available." })
    end
  end
end
