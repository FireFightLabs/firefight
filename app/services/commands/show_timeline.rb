module Commands
  class ShowTimeline
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS

    def self.execute(command)
      incident = command.workspace.incidents.in_channel(command.channel_id).recent.first
      return Command.ephemeral("This command must be run from an incident channel.") unless incident

      command.workspace.adapter.open_timeline_modal(trigger_id: command.trigger_id, incident: incident)
      nil
    end
  end
end
