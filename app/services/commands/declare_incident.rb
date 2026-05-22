module Commands
  # Handles opening the incident creation modal
  # Platform-agnostic handler that delegates to platform-specific adapters
  class DeclareIncident
    def self.execute(command)
      workspace = command.workspace
      raise ArgumentError, "Workspace not found" unless workspace

      workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::IncidentCreation.build(workspace: workspace))
    rescue AdapterError::TriggerExpired
      { response_type: Command::EPHEMERAL, text: "The command timed out. Please try again." }
    end
  end
end
