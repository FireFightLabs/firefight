class IncidentInviteService
  def initialize(workspace)
    @workspace = workspace
    @adapter = workspace.adapter
  end

  def invite!(incident:, user_ids:)
    invited_user_ids = []
    already_in_channel_user_ids = []
    failed_invites = []

    normalized_user_ids(user_ids).each do |user_id|
      begin
        @adapter.invite_user(channel_id: incident.channel_id, user_id: user_id)
        invited_user_ids << user_id
      rescue AdapterError::AlreadyInChannel
        already_in_channel_user_ids << user_id
      rescue AdapterError => e
        failed_invites << { user_id: user_id, error: e.message }
      end
    end

    {
      invited_user_ids: invited_user_ids,
      already_in_channel_user_ids: already_in_channel_user_ids,
      failed_invites: failed_invites
    }
  end

  def resolve_and_notify!(incident:, text:, channel_id:, user_id:)
    targets = @adapter.resolve_people(text)

    if targets[:user_ids].empty?
      message = if targets[:had_target_tokens]
        "Couldn't resolve #{targets[:unresolved_handles].map { |h| "@#{h}" }.join(', ')}. Try `/ff invite` to pick responders from the modal."
      else
        "No users specified. Try `/ff invite @alice @bob` or `/ff invite` to pick responders from the modal."
      end
      @adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: message)
      return
    end

    result = invite!(incident: incident, user_ids: targets[:user_ids])
    @adapter.post_ephemeral(channel_id: channel_id, user_id: user_id, text: summary_message(result))
  end

  def summary_message(result)
    invited_count = result[:invited_user_ids].size
    already_count = result[:already_in_channel_user_ids].size
    failed_count = result[:failed_invites].size

    parts = []
    parts << "Invited #{invited_count} responder#{'s' unless invited_count == 1}." if invited_count.positive?
    if already_count.positive?
      mentions = result[:already_in_channel_user_ids].map { |id| "<@#{id}>" }.join(", ")
      verb = already_count == 1 ? "is" : "are"
      parts << "#{mentions} #{verb} already in this channel."
    end
    parts << "#{failed_count} failed." if failed_count.positive?
    parts = [ "No responders were invited." ] if parts.empty?

    parts.join(" ")
  end

  private

  def normalized_user_ids(user_ids)
    Array(user_ids).compact.map(&:to_s).uniq
  end
end
