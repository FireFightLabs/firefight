# Who is reminded of what nobody confirmed. A memory a person taught goes to that person, about their own knowledge
# only. What runs and incidents taught goes to the incident's channel, or to the workspace admins when there is no
# channel to ask in. Each person or channel hears at most once a week, only when something waits, and never about the
# same memory twice in a row.
module Chat::Memory::Reminders
  # A memory is reminded about once it has waited this long, so the message that asked when it was learned comes first.
  WAITED = 3.days
  # Just under a week, so a weekly run that starts a little late still reaches everyone it reached the week before.
  GAP = 6.days
  PER_MESSAGE = 5

  # One message to send. recipient is a member to message directly, or nil for the incident's channel.
  Reminder = Data.define(:recipient, :incident, :memories)

  # What the team taught, to each incident's channel that is still there to ask in.
  def self.in_channels(workspace, now: Time.current)
    team_by_incident(workspace, now).filter_map do |incident, memories|
      reminder(workspace, now, recipient: nil, incident: incident, memories: memories) if incident&.channel_id.present?
    end
  end

  # What each person taught, to them, and what the team taught with no channel to ask in, to the admins. unposted is
  # what an incident's channel could not take this time, such as one archived since.
  def self.direct(workspace, now: Time.current, unposted: [])
    for_admins = team_by_incident(workspace, now).reject { |incident, _| incident&.channel_id.present? }.values.flatten + unposted
    people = waiting(workspace, now).select(&:added_by_id).group_by(&:added_by)
    admins = for_admins.empty? ? [] : Ability::PackRequest.admins_of(workspace).to_a
    (people.keys | admins).filter_map do |member|
      reminder(workspace, now, recipient: member, incident: nil, memories: (people[member] || []) + (admins.include?(member) ? for_admins : []))
    end
  end

  def self.waiting(workspace, now)
    Chat::Memory.where(workspace: workspace, state: Chat::Memory::STATE_UNCONFIRMED).where(created_at: ...now - WAITED)
                .includes(:added_by, :source).order(:created_at).to_a
  end
  private_class_method :waiting

  # A memory from an incident, from a run on one or from a chat about one belongs to that incident.
  def self.team_by_incident(workspace, now)
    waiting(workspace, now).reject(&:added_by_id).group_by do |memory|
      memory.source.is_a?(Incident) ? memory.source : memory.source.try(:incident)
    end
  end
  private_class_method :team_by_incident

  def self.reminder(workspace, now, recipient:, incident:, memories:)
    return nil if recipient && recipient.platform_user_id.blank?

    sent = Chat::MemoryPost.reminders.where(workspace: workspace, recipient: recipient, incident: (incident unless recipient))
    return nil if sent.exists?(created_at: (now - GAP)..)

    last = sent.order(created_at: :desc).first&.memory_ids.to_a
    visible = recipient && Chat::Memory.visible_to(recipient, workspace).where(id: memories.map(&:id)).pluck(:id).to_set
    shown = memories.uniq.reject { |memory| last.include?(memory.id) || (visible && !visible.include?(memory.id)) }.first(PER_MESSAGE)
    shown.empty? ? nil : Reminder.new(recipient: recipient, incident: incident, memories: shown)
  end
  private_class_method :reminder
end
