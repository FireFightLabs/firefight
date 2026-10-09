# Asks people to decide on memories: an incident's channel about those the incident or its postmortem taught and those a
# chat or run working on it learned or disputed, a dashboard chat about one something contradicted, and once a week
# whoever should know about what nobody confirmed. Each message keeps the memories it showed, and redraws them as
# people decide.
class MemoryPostService
  # What a platform message shows, so the adapter never reads a memory record. reminder is set for a reminder.
  Shown = Data.define(:post_id, :kind, :incident_identifier, :memories, :reminder) do
    def initialize(post_id:, kind:, incident_identifier:, memories:, reminder: nil) = super
  end
  ShownMemory = Data.define(:id, :text, :about, :about_removed, :state, :reason, :decided_by, :correction)
  # What a reminder is about: how many of its memories the person it went to taught, how many the team's runs and
  # incidents taught, and whether it went to a person rather than a channel.
  ShownReminder = Data.define(:taught, :learned, :direct)

  NOT_POSTED = [ AdapterError::IsArchived, AdapterError::NotFound, AdapterError::NotInChannel ].freeze

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

  # A memory something contradicted in a dashboard chat, asked about in a card there. evidence is what showed it wrong.
  def ask_in_chat!(conversation, memory, evidence:)
    post = Chat::MemoryPost.create!(workspace: @workspace, conversation: conversation, kind: Chat::MemoryPost::KIND_DISPUTED,
                                    memory_ids: [ memory.id ], evidence: evidence)
    Conversation::LiveDelivery.memory_asked(conversation)
    post
  end

  # This week's reminders about what nobody confirmed. One whose incident channel cannot take it, such as one archived
  # since, goes to the workspace admins instead. Returns how many were sent.
  def remind!(now: Time.current)
    in_channels = Chat::Memory::Reminders.in_channels(@workspace, now: now)
    unposted = in_channels.reject { |reminder| remind(reminder) }
    direct = Chat::Memory::Reminders.direct(@workspace, now: now, unposted: unposted.flat_map(&:memories))
    in_channels.size - unposted.size + direct.count { |reminder| remind(reminder) }
  end

  # Someone pressing Confirm or Not right. reference is the post a button names, or the incident on a message posted
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

    replacement = memory.reject!(by: member, reason: reason.presence || "Corrected in #{post.place}", correction: correction.strip)
    return memory.reject_blocked_reason unless replacement

    redraw(post)
    nil
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  def shown(post)
    memories = post.memories
    Shown.new(post_id: post.id, kind: post.kind, incident_identifier: post.incident&.identifier, memories: memories.map { |memory| shown_memory(memory) },
              reminder: (shown_reminder(post, memories) if post.kind == Chat::MemoryPost::KIND_REMINDER))
  end

  private

  def shown_reminder(post, memories)
    taught = memories.count { |memory| post.recipient_id && memory.added_by_id == post.recipient_id }
    ShownReminder.new(taught: taught, learned: memories.size - taught, direct: post.recipient_id.present?)
  end

  # Sends one reminder, by direct message or in the incident's channel. Returns false when it could not be posted.
  def remind(reminder)
    channel_id = reminder.recipient ? reminder.recipient.platform_user_id : reminder.incident.channel_id
    post = Chat::MemoryPost.create!(workspace: @workspace, kind: Chat::MemoryPost::KIND_REMINDER, recipient: reminder.recipient,
                                    incident: (reminder.incident unless reminder.recipient), channel_id: channel_id,
                                    memory_ids: reminder.memories.map(&:id))
    posted = adapter.post_learned_memories(channel_id: channel_id, thread_id: nil, post: shown(post))
    post.posted!(posted[:message_id], channel_id: posted[:channel_id] || channel_id)
    true
  rescue AdapterError => error
    post&.destroy!
    Rails.logger.info({ event: "memory_post.reminder_not_posted", workspace_id: @workspace.id, error: error.class.name }.to_json)
    false
  end

  def shown_memory(memory)
    ShownMemory.new(id: memory.id, text: memory.text, about: memory.about, about_removed: memory.about_removed?, state: memory.state,
                    reason: memory.state_reason, decided_by: (memory.decider if [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_REJECTED ].include?(memory.state)),
                    correction: memory.replaced_by&.text)
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
