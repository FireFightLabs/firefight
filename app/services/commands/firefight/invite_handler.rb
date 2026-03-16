module Commands
  module Firefight
    class InviteHandler
      def self.execute(command)
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless command.workspace
        return ephemeral("This command must be run from an active incident channel.") unless command.incident

        service = IncidentInviteService.new(command.workspace)
        targets = service.resolve_invitees(command.text)

        if targets[:user_ids].empty?
          if targets[:had_target_tokens]
            unresolved = targets[:unresolved_handles]
            return ephemeral("Couldn't resolve #{unresolved.map { |h| "@#{h}" }.join(', ')}. Try `/ff invite` to pick responders from the modal.")
          end

          command.workspace.adapter.open_invite_responders_modal(trigger_id: command.trigger_id, incident: command.incident)
          return nil
        end

        result = service.invite!(incident: command.incident, user_ids: targets[:user_ids])
        ephemeral(service.summary_message(result))
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff invite` again.")
      end

      private_class_method def self.ephemeral(text)
        { response_type: Command::EPHEMERAL, text: text }
      end
    end
  end
end
