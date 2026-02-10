module Commands
  # Handles opening the incident creation modal
  # Platform-agnostic handler that delegates to platform-specific adapters
  class ModalHandler
    def self.execute(command)
      workspace = command.workspace
      raise ArgumentError, "Workspace not found" unless workspace

      adapter = WorkspaceAdapter.for(workspace)
      adapter.open_modal(
        trigger_id: command.trigger_id,
        view: Slack::ModalBuilder.incident_creation_form
      )
    rescue AdapterError::TriggerExpired
      { response_type: "ephemeral", text: "The command timed out. Please try again." }
    end
  end
end
