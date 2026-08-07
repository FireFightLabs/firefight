module Interactions
  # Retired button on older messages: redraw rather than do nothing.
  class ApplyRunbookHandler
    def self.execute(interaction)
      workspace = interaction.workspace
      incident_runbook = workspace.incident_runbooks.find(interaction.action_value)

      RunbookAttachmentService.new(workspace).refresh_message(incident_runbook)

      nil
    rescue ActiveRecord::RecordNotFound
      nil
    end
  end
end
