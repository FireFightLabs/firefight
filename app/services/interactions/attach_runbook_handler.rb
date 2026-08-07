module Interactions
  class AttachRunbookHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      metadata = Slack::PrivateMetadata.parse(interaction.private_metadata)
      incident = workspace.incidents.find(metadata.incident_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: interaction.user_id)
      slug = interaction.values.dig("runbook_block", "runbook_select", "selected_option", "value")

      RunbookAttachmentService.new(workspace).attach_by_slug(
        incident: incident, slug: slug, attached_by: member
      )

      { response_action: "clear" }
    rescue ActiveRecord::RecordNotFound
      { response_action: "errors", errors: { "runbook_block" => "That runbook is no longer available." } }
    end
  end
end
