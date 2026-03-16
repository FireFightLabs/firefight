class IncidentInviteService
  def initialize(workspace)
    @workspace = workspace
    @adapter = workspace.adapter
  end

  def resolve_invitees(text)
    text_str = text.to_s
    mention_ids = text_str.scan(/<@([A-Z0-9]+)(?:\|[^>]+)?>/).flatten
    raw_ids = text_str.scan(/\bU[A-Z0-9]{8,}\b/)

    handles_source = text_str.gsub(/<@[^>]+>/, "")
    handle_tokens = handles_source.scan(/@([a-z0-9._-]+)/i).flatten.map(&:downcase)
    resolved_handle_ids, unresolved_handles = resolve_handles(handle_tokens)

    {
      user_ids: (mention_ids + raw_ids + resolved_handle_ids).uniq,
      unresolved_handles: unresolved_handles,
      had_target_tokens: mention_ids.any? || raw_ids.any? || handle_tokens.any?
    }
  end

  def invite!(incident:, user_ids:)
    invited_user_ids = []
    already_in_channel_user_ids = []
    failed_invites = []

    normalized_user_ids(user_ids).each do |user_id|
      begin
        @adapter.invite_user(channel_id: incident.channel_id, user_id: user_id)
        invited_user_ids << user_id
      rescue AdapterError => e
        if already_in_channel_error?(e)
          already_in_channel_user_ids << user_id
        else
          failed_invites << { user_id: user_id, error: e.message }
        end
      end
    end

    {
      invited_user_ids: invited_user_ids,
      already_in_channel_user_ids: already_in_channel_user_ids,
      failed_invites: failed_invites
    }
  end

  def summary_message(result)
    invited_count = result[:invited_user_ids].size
    already_count = result[:already_in_channel_user_ids].size
    failed_count = result[:failed_invites].size

    parts = []
    parts << "Invited #{invited_count} responder#{'s' unless invited_count == 1}." if invited_count.positive?
    parts << "#{already_count} already in channel." if already_count.positive?
    parts << "#{failed_count} failed." if failed_count.positive?
    parts = [ "No responders were invited." ] if parts.empty?

    parts.join(" ")
  end

  private

  def normalized_user_ids(user_ids)
    Array(user_ids).compact.map(&:to_s).uniq
  end

  def already_in_channel_error?(error)
    message = error.message.to_s
    message.include?("already_in_channel") || message.include?("cant_invite_self")
  end

  def resolve_handles(handles)
    return [ [], [] ] if handles.empty?

    aliases_to_user_ids = {}
    @workspace.workspace_memberships.includes(:user).find_each do |membership|
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
      fallback = @adapter.resolve_user_ids_from_handles(handles: unresolved)
      resolved_ids.concat(fallback[:resolved_user_ids])
      unresolved = fallback[:unresolved_handles]
    end

    [ resolved_ids.uniq, unresolved.uniq ]
  rescue AdapterError => e
    Rails.logger.warn({
      event: "firefight.invite.handle_resolution_failed",
      workspace_id: @workspace.id,
      error: e.message
    })
    [ resolved_ids.uniq, unresolved.uniq ]
  end

  def aliases_for_membership(membership)
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
end
