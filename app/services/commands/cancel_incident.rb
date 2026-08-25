module Commands
  # Cancelling is for an incident that turned out not to be one, a false
  # positive, a duplicate, a test. That should cost one command, so the modal
  # only appears when a workspace has attached something worth asking.
  class CancelIncident
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(command)
      return Command.ephemeral("This command must be run from an incident channel.") unless command.incident

      workspace = command.workspace
      incident = command.incident

      # The resolved set is what the modal renders, so an empty one means there
      # is nothing to ask and the command should just cancel.
      return open_modal(command) if IncidentFormResolver.new(workspace).fields_for(incident, IncidentForm::SLUG_CANCEL).any?

      cancel!(workspace, incident, command.user_id)
      nil
    end

    def self.open_modal(command)
      ModalOpener.open(
        :cancel,
        workspace: command.workspace,
        incident: command.incident,
        trigger_id: command.trigger_id,
        user_id: command.user_id
      )
      nil
    end

    def self.cancel!(workspace, incident, platform_user_id)
      member = workspace.workspace_memberships.find_by!(platform_user_id: platform_user_id)
      IncidentLifecycleService.new(workspace).cancel_with_default_status(incident, changed_by: member)
    end
  end
end
