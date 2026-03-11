module Commands
  module Firefight
    class InviteHandler
      def self.execute(command)
        workspace = command.workspace
        return ephemeral("Workspace not found. Please reinstall Firefight.") unless workspace

        incident = workspace.incidents.active.in_channel(command.channel_id).first
        return ephemeral("This command must be run from an active incident channel.") unless incident

        parsed_targets = parse_targets(workspace, command.text)
        user_ids = parsed_targets[:user_ids]
        if user_ids.empty?
          if parsed_targets[:had_target_tokens]
            unresolved = parsed_targets[:unresolved_handles]
            return ephemeral("Couldn't resolve #{unresolved.map { |h| "@#{h}" }.join(', ')}. Try `/ff invite` to pick responders from the modal.")
          end

          adapter = WorkspaceAdapter.for(workspace)
          adapter.open_invite_responders_modal(trigger_id: command.trigger_id, incident: incident)
          return nil
        end

        result = IncidentInviteService.new(workspace).invite!(incident: incident, user_ids: user_ids)
        ephemeral(summary_message(result))
      rescue AdapterError::TriggerExpired
        ephemeral("This command has expired. Please try `/ff invite` again.")
      end

      private_class_method def self.parse_targets(workspace, text)
        text_str = text.to_s
        mention_ids = text_str.scan(/<@([A-Z0-9]+)(?:\|[^>]+)?>/).flatten
        raw_ids = text_str.scan(/\bU[A-Z0-9]{8,}\b/)

        handles_source = text_str.gsub(/<@[^>]+>/, "")
        handle_tokens = handles_source.scan(/@([a-z0-9._-]+)/i).flatten.map(&:downcase)
        resolved_handle_ids, unresolved_handles = resolve_handles(workspace, handle_tokens)

        {
          user_ids: (mention_ids + raw_ids + resolved_handle_ids).uniq,
          unresolved_handles: unresolved_handles,
          had_target_tokens: mention_ids.any? || raw_ids.any? || handle_tokens.any?
        }
      end

      private_class_method def self.resolve_handles(workspace, handles)
        return [ [], [] ] if handles.empty?

        aliases_to_user_ids = {}
        workspace.workspace_memberships.includes(:user).find_each do |membership|
          aliases_for_membership(membership).each do |handle_alias|
            aliases_to_user_ids[handle_alias] ||= membership.platform_user_id
          end
        end

        resolved_ids = []
        unresolved = []
        handles.each do |handle|
          user_id = aliases_to_user_ids[handle]
          if user_id
            resolved_ids << user_id
          else
            unresolved << handle
          end
        end

        if unresolved.any?
          adapter = WorkspaceAdapter.for(workspace)
          fallback = adapter.resolve_user_ids_from_handles(handles: unresolved)
          resolved_ids.concat(fallback[:resolved_user_ids])
          unresolved = fallback[:unresolved_handles]
        end

        [ resolved_ids.uniq, unresolved.uniq ]
      rescue AdapterError => e
        Rails.logger.warn({
          event: "firefight.invite.handle_resolution_failed",
          workspace_id: workspace.id,
          error: e.message
        })
        [ resolved_ids.uniq, unresolved.uniq ]
      end

      private_class_method def self.aliases_for_membership(membership)
        aliases = []
        user = membership.user

        aliases << user.email.to_s.split("@").first.downcase if user.email.present?

        if user.name.present?
          normalized_name = user.name.downcase
          aliases << normalized_name.gsub(/\s+/, "")
          aliases << normalized_name.gsub(/\s+/, ".")
          aliases.concat(normalized_name.split)
        end

        platform_data = membership.platform_data || {}
        %w[display_name display_name_normalized name real_name].each do |key|
          value = platform_data[key]
          aliases << value.downcase if value.present?
        end

        aliases.compact.uniq
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
