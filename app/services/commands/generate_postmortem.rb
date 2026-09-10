module Commands
  class GeneratePostmortem
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(command)
      incident = command.workspace.incidents.closed.in_channel(command.channel_id).first
      unless incident
        # For a canceled incident "must be run from a closed channel" reads like a mistake.
        canceled = command.workspace.incidents.canceled.in_channel(command.channel_id).first
        return Command.ephemeral("#{canceled.identifier} was canceled, so it has no postmortem to write.") if canceled

        return Command.ephemeral("This command must be run from a resolved incident channel.")
      end
      member = command.workspace.workspace_memberships.find_by(platform_user_id: command.user_id)
      return Command.ephemeral(PostmortemGenerationService::UNKNOWN_MEMBER_MESSAGE) unless member

      # Shares the dashboard's placeholder, so a second request while one runs is a no-op.
      Command.ephemeral(PostmortemGenerationService.new(command.workspace).request!(incident, by: member).message)
    end
  end
end
