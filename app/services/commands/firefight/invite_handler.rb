module Commands
  module Firefight
    class InviteHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("This command must be run from an active incident channel.") unless incident

        user_ids = parse_user_ids(command.text)
        if user_ids.empty?
          adapter = WorkspaceAdapter.for(workspace)
          adapter.open_invite_responders_modal(trigger_id: command.trigger_id, incident: incident)
          return nil
        end

        result = IncidentInviteService.new(workspace).invite!(incident: incident, user_ids: user_ids)
        ephemeral(summary_message(result))
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff invite` again.")
      end

      private_class_method def self.parse_user_ids(text)
        mention_ids = text.to_s.scan(/<@([A-Z0-9]+)(?:\|[^>]+)?>/).flatten
        raw_ids = text.to_s.scan(/\bU[A-Z0-9]{8,}\b/)
        (mention_ids + raw_ids).uniq
      end

      private_class_method def self.summary_message(result)
        parts = []
        invited_count = result[:invited_user_ids].size
        already_count = result[:already_in_channel_user_ids].size
        failed_count = result[:failed_invites].size

        parts << "Invited #{invited_count} responder#{'s' unless invited_count == 1}." if invited_count.positive?
        parts << "#{already_count} already in channel." if already_count.positive?
        parts << "#{failed_count} failed." if failed_count.positive?
        parts = [ "No responders were invited." ] if parts.empty?

        parts.join(" ")
      end

      private_class_method def self.ephemeral(text)
        { response_type: "ephemeral", text: text }
      end
    end
  end
end
