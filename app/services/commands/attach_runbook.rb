module Commands
  class AttachRunbook
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      available = command.incident.attachable_runbooks
      if available.empty?
        return Command.ephemeral(
          "Every runbook is already attached to this incident, or none are set up yet. Add them in Settings, then run `/ff runbook` again."
        )
      end

      adapter = command.workspace.adapter
      adapter.open_modal(
        trigger_id: command.trigger_id,
        view: adapter.build_modal(PlatformAdapter::Modal::ATTACH_RUNBOOK, command.incident, available)
      )
      nil
    end
  end
end
