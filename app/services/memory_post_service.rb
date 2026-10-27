# Tells an incident's channel about memories: those the incident or its postmortem taught and those a chat or run working
# on it learned or disputed. Nobody is asked to confirm them, since Halon checks every memory against production each
# night, but anyone may mark one not right or correct it there. Each message keeps the memories it showed, and redraws
# them as people decide. Messages and chat cards posted before Halon checked memories itself still take their buttons.
class MemoryPostService
  # What a platform message shows, so the adapter never reads a memory record. reminder is set for an earlier reminder.
  # approved_lesson is set when a direct message went to the person who approved the lesson it shows for pull request reviews.
  Shown = Data.define(:post_id, :kind, :incident_identifier, :memories, :reminder, :approved_lesson) do
    def initialize(post_id:, kind:, incident_identifier:, memories:, reminder: nil, approved_lesson: false) = super
  end
  # checked_by_halon is set when Halon's check alone confirmed it, and approved_by names who approved it as a lesson for
  # pull request reviews when no person confirmed it.
  ShownMemory = Data.define(:id, :text, :about, :about_removed, :state, :reason, :decided_by, :correction, :checked_by_halon, :approved_by)
  # What an earlier reminder was about: how many of its memories the person it went to taught, how many the team's runs and
  # incidents taught, and whether it went to a person rather than a channel.
  ShownReminder = Data.define(:taught, :learned, :direct)

  NOT_POSTED = [ AdapterError::IsArchived, AdapterError::NotFound, AdapterError::NotInChannel ].freeze
  # Errors that pass, so the job sending the message tries again rather than giving up.
  PASSING = [ AdapterError::RateLimited, AdapterError::ServerError, AdapterError::Unavailable ].freeze

  def initialize(workspace)
    @workspace = workspace
  end

  # Returns the post, or nil when there is no channel to post in. A channel archived since keeps the memories on the
  # Memory page instead, where the badge shows them.
  def post!(incident, memories, kind:, thread_id: nil)
    return nil if memories.empty? || incident.channel_id.blank?

    post = Chat::MemoryPost.create!(workspace: @workspace, incident: incident, kind: kind, channel_id: incident.channel_id,
                                    thread_id: thread_id, memory_ids: memories.map(&:id))
    posted = adapter.post_learned_memories(channel_id: post.channel_id, thread_id: thread_id, post: shown(post))
    post.posted!(posted[:message_id], channel_id: posted[:channel_id] || post.channel_id)
    post
  rescue *NOT_POSTED => error
    post&.destroy!
    Rails.logger.info({ event: "memory_post.not_posted", incident_id: incident.id, kind: kind, error: error.class.name }.to_json)
    nil
  end

  # A chat or run working on an incident learned a memory or disputed one, so the channel hears it, in the thread the
  # chat or run speaks in when it has one there.
  def note!(memory, kind:, owner:)
    incident = owner.incident
    return nil unless incident

    thread_id = owner.thread_id if owner.channel_id.present? && owner.channel_id == incident.channel_id
    post!(incident, [ memory ], kind: kind, thread_id: thread_id)
  end

  # Halon's nightly check found evidence against a memory a person stands behind, so whoever confirmed it and whoever
  # approved it as a lesson for pull request reviews are each told once by direct message, with Still right, Not right
  # and Edit. Nothing is sent to one without a platform account, or when the platform cannot take it, and the memory
  # waits on the Memory page either way. Returns the posts sent.
  def tell_people_behind!(memory)
    return [] unless memory.state == Chat::Memory::STATE_DISPUTED && @workspace.platform.present?

    [ memory.confirmed_by, memory.approved_by ].compact.uniq.filter_map { |person| tell_person_behind!(memory, person) }
  end

  # Someone pressing Still right or Not right, or Confirm on a message posted before Halon checked memories itself. reference is the post a button names, or the incident on a message posted
  # before posts were kept. Returns false when the memory is not one the message shows.
  def decide!(reference:, memory_id:, member:, confirmed:, channel_id:, message_id:)
    post = post_for(reference, channel_id: channel_id, message_id: message_id)
    memory = post && visible(post, member).find { |each| each.id == memory_id }
    return false unless memory

    if confirmed
      memory.confirm!(by: member)
    else
      memory.reject!(by: member, reason: "Marked not right in #{post.place}")
    end
    redraw(post)
    true
  end

  # The memory a Correct button names, as the form asking what is right instead shows it, or nil when the message does
  # not show it or it is about a resource outside member's map reach.
  def correctable(post_id:, memory_id:, member:)
    post = Chat::MemoryPost.find_by(workspace: @workspace, id: post_id)
    memory = post && visible(post, member).find { |each| each.id == memory_id }
    memory && shown_memory(memory)
  end

  # Someone writing what is right instead. Returns why it was refused, or nil once the correction replaced it.
  def correct!(post_id:, memory_id:, member:, correction:, reason:)
    post = Chat::MemoryPost.find_by(workspace: @workspace, id: post_id)
    memory = post && visible(post, member).find { |each| each.id == memory_id }
    return "That memory is gone. Close this and look on the Memory page." unless memory
    return "Write what is right instead." if correction.blank?

    replacement = memory.edit_by!(by: member, words: correction, reason: reason.presence || "Corrected in #{post.place}", source: AbilityGateway::SOURCE_SLACK)
    return memory.edit_blocked_reason(member) unless replacement

    redraw(post)
    nil
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  def shown(post)
    memories = post.memories
    Shown.new(post_id: post.id, kind: post.kind, incident_identifier: post.incident&.identifier, memories: memories.map { |memory| shown_memory(memory) },
              reminder: (shown_reminder(post, memories) if post.kind == Chat::MemoryPost::KIND_REMINDER),
              approved_lesson: post.kind == Chat::MemoryPost::KIND_CHALLENGED && post.recipient_id.present? && memories.any? { |memory| memory.approved_by_id == post.recipient_id })
  end

  private

  def tell_person_behind!(memory, person)
    return nil if person.platform_user_id.blank? || person.removed? || !Chat::Memory.visible_to(person, @workspace).exists?(id: memory.id)
    return nil if told_already?(memory, person)

    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: person, channel_id: person.platform_user_id,
                                    memory_ids: [ memory.id ], evidence: memory.state_reason)
    posted = adapter.post_learned_memories_to_user(user_id: person.platform_user_id, post: shown(post))
    post.posted!(posted[:message_id], channel_id: posted[:channel_id] || post.channel_id)
    post
  rescue *PASSING => error
    post&.destroy!
    raise error
  rescue AdapterError => error
    post&.destroy!
    Rails.logger.info({ event: "memory_post.person_behind_not_told", memory_id: memory.id, error: error.class.name }.to_json)
    nil
  end

  # The person was told about this memory with these very words already, so a second job for the same dispute sends nothing.
  def told_already?(memory, person)
    Chat::MemoryPost.where(workspace: @workspace, kind: Chat::MemoryPost::KIND_CHALLENGED, recipient: person).where("? = ANY(memory_ids)", memory.id)
                    .any? { |post| post.evidence == memory.state_reason }
  end

  def shown_reminder(post, memories)
    taught = memories.count { |memory| post.recipient_id && memory.added_by_id == post.recipient_id }
    ShownReminder.new(taught: taught, learned: memories.size - taught, direct: post.recipient_id.present?)
  end

  def shown_memory(memory)
    ShownMemory.new(id: memory.id, text: memory.text, about: memory.about, about_removed: memory.about_removed?, state: memory.state,
                    reason: memory.state_reason, decided_by: (memory.decider if [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_REJECTED ].include?(memory.state)),
                    correction: memory.replaced_by&.text, checked_by_halon: memory.checked_by_halon_alone?,
                    approved_by: (memory.approved_by&.display_name if memory.approved? && memory.confirmed_by_id.nil?))
  end

  # A memory about a resource outside the person's map reach answers as one the message does not show.
  def visible(post, member)
    allowed = Chat::Memory.visible_to(member, @workspace).where(id: post.memory_ids).pluck(:id).to_set
    post.memories.select { |memory| allowed.include?(memory.id) }
  end

  def adapter = @adapter ||= @workspace.adapter

  def redraw(post)
    return if post.message_id.blank?

    adapter.update_learned_memories(channel_id: post.channel_id, message_id: post.message_id, post: shown(post))
  rescue *NOT_POSTED => error
    Rails.logger.info({ event: "memory_post.not_redrawn", post_id: post.id, error: error.class.name }.to_json)
  end

  # A message from before posts were kept names its incident, and showed every lesson the incident had.
  def post_for(reference, channel_id: nil, message_id: nil)
    post = Chat::MemoryPost.find_by(workspace: @workspace, id: reference)
    return post if post

    incident = @workspace.incidents.find_by(id: reference)
    return nil unless incident

    ids = Chat::Memory.where(workspace: @workspace, source: incident).order(:created_at).pluck(:id)
    Chat::MemoryPost.new(workspace: @workspace, incident: incident, kind: Chat::MemoryPost::KIND_INCIDENT, memory_ids: ids,
                         channel_id: channel_id || incident.channel_id, message_id: message_id)
  end
end
