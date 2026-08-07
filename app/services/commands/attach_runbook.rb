module Commands
  class AttachRunbook
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      available = available_runbooks(command)
      if available.empty?
        return Command.ephemeral(
          "Every runbook is already attached to this incident, or none are set up yet. Add them in Settings, then run `/ff runbook` again."
        )
      end

      command.workspace.adapter.open_modal(
        trigger_id: command.trigger_id,
        view: Slack::Modals::AttachRunbook.build(command.incident, available)
      )
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff runbook` again.")
    end

    def self.available_runbooks(command)
      attached = command.incident.incident_runbooks.pluck(:runbook_id)
      command.workspace.runbooks.active.ordered.where.not(id: attached)
    end
  end
end
