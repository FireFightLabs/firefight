class IncidentInviteService
  # What one invite round did, in the platform ids the platform was asked
  # about.
  Result = Data.define(:invited_user_ids, :already_in_channel_user_ids, :failed_invites)

  def initialize(workspace)
    @workspace = workspace
    @adapter = workspace.adapter
  end

  # `people` are members, platform user ids, or a mix, so a caller that knows
  # someone as a member never has to reach for their platform account.
  def invite!(incident:, people:)
    user_ids = platform_user_ids(people)
    invited = []
    already_in_channel = []
    failed = []

    user_ids.each do |user_id|
      @adapter.invite_user(channel_id: incident.channel_id, user_id: user_id)
      invited << user_id
    rescue AdapterError::AlreadyInChannel
      already_in_channel << user_id
    rescue AdapterError => e
      failed << { user_id: user_id, error: e.message }
    end

    Result.new(
      invited_user_ids: invited,
      already_in_channel_user_ids: already_in_channel,
      failed_invites: failed
    )
  end

  def resolve_and_notify!(incident:, text:, channel_id:, user_id:)
    targets = @adapter.resolve_people(text)

    if targets[:user_ids].empty?
      @adapter.post_invite_unresolved(channel_id: channel_id, user_id: user_id, targets: targets)
      return
    end

    result = invite!(incident: incident, people: targets[:user_ids])
    @adapter.post_invite_summary(channel_id: channel_id, user_id: user_id, result: result)
  end

  private

  def platform_user_ids(people)
    Array(people).compact.map do |person|
      person.is_a?(WorkspaceMembership) ? person.platform_user_id : person.to_s
    end.uniq
  end
end
