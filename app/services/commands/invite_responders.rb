module Commands
  class InviteResponders
    extend HandlerAuthorization
    authorize_as Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE

    def self.execute(command)
      return Command.ephemeral("This command must be run from an active incident channel.") unless command.incident

      # No invitees in the text → open the picker modal. Must stay sync. trigger_id expires in 3s.
      unless Slack::HandleResolver.target_tokens?(command.text)
        command.workspace.adapter.open_modal(trigger_id: command.trigger_id, view: Slack::Modals::Invite.build(command.incident))
        return nil
      end

      IncidentInviteJob.perform_later(
        workspace_id: command.workspace.id,
        incident_id: command.incident.id,
        text: command.text,
        channel_id: command.channel_id,
        user_id: command.user_id
      )
      Command.ephemeral(":hourglass_flowing_sand: Inviting…")
    end
  end
end
