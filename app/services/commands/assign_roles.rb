module Commands
  class AssignRoles
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      roles = command.workspace.incident_roles.active.ordered
      return Command.ephemeral("No incident roles are set up yet. Add them in Settings, then run `/ff roles` again.") if roles.empty?

      command.workspace.adapter.open_modal(
        trigger_id: command.trigger_id,
        view: Slack::Modals::Roles.build(command.incident, roles)
      )
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff roles` again.")
    end
  end
end
