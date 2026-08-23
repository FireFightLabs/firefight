module Commands
  class AttachRunbook
    extend HandlerAuthorization
    authorize_as ApiKey::RESOURCE_INCIDENTS

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      available = command.incident.attachable_runbooks
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
    end
  end
end
