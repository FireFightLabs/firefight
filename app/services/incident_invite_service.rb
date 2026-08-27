class IncidentInviteService
  # What one invite round did, holding the people it was asked about rather
  # than the platform ids it derived from them. A caller that named members
  # gets members back and never has to reverse the mapping.
  Result = Data.define(:invited, :already_in_channel, :failed)
  Failure = Data.define(:person, :error)

  def initialize(workspace)
    @workspace = workspace
    @adapter = workspace.adapter
  end

  # `people` are members, platform user ids, or a mix, so a caller that knows
  # someone as a member never has to reach for their platform account.
  def invite!(incident:, people:)
    blocked_reason = incident.invite_blocked_reason
    raise Incident::NotActive, blocked_reason if blocked_reason

    invited = []
    already_in_channel = []
    failed = []

    distinct(people).each do |person|
      @adapter.invite_user(channel_id: incident.channel_id, user_id: platform_user_id(person))
      invited << person
    rescue AdapterError::AlreadyInChannel
      already_in_channel << person
    rescue AdapterError => e
      failed << Failure.new(person: person, error: e.message)
    end

    Result.new(invited: invited, already_in_channel: already_in_channel, failed: failed)
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

  # Two references can name one person, and the platform is what decides that,
  # so the round is deduped by the account it will be asked about.
  def distinct(people)
    Array(people).compact.uniq { |person| platform_user_id(person) }
  end

  def platform_user_id(person)
    person.is_a?(WorkspaceMembership) ? person.platform_user_id : person.to_s
  end
end
