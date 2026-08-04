module Commands
  # Cancelling is for an incident that turned out not to be one: a false
  # positive, a duplicate, a test. That should cost one command, so the modal
  # only appears when a workspace has attached something worth asking.
  class CancelIncident
    def self.execute(command)
      return Command.ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
      return Command.ephemeral("This command must be run from an incident channel.") unless command.incident

      workspace = command.workspace
      incident = command.incident

      # Asks what the modal would actually render, not what the form lists.
      # Status is configurable on this form but is not shown while there is a
      # single canceled status, so the field set alone would open an empty one.
      return open_modal(command) if Slack::Modals::IncidentCancel.renderable_blocks(incident).any?

      cancel!(workspace, incident, command.user_id)
      nil
    rescue AdapterError::TriggerExpired
      Command.ephemeral("This command has expired. Please try `/ff cancel` again.")
    end

    def self.open_modal(command)
      CancelModalOpener.open(
        workspace: command.workspace,
        incident: command.incident,
        trigger_id: command.trigger_id,
        user_id: command.user_id
      )
      nil
    end

    def self.cancel!(workspace, incident, platform_user_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: platform_user_id)
      status = workspace.incident_statuses.canceled.active.ordered.first

      raise ActiveRecord::RecordNotFound, "no canceled status configured" if status.nil?

      IncidentLifecycleService.new(workspace).cancel(
        incident, { incident_status: status }, changed_by: member
      )
    end
  end
end
