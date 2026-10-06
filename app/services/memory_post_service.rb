# Asks an incident's channel to decide on memories, those the incident or its postmortem taught and those a chat or run
# working on it learned or disputed. Each message keeps the memories it showed, and redraws them as people decide.
class MemoryPostService
  # What a platform message shows, so the adapter never reads a memory record.
  Shown = Data.define(:post_id, :kind, :incident_identifier, :memories)
  ShownMemory = Data.define(:id, :text, :about, :about_removed, :state, :reason, :decided_by, :correction)

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
    post.posted!(posted[:message_id])
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

  # Someone pressing Confirm or Not right. reference is the post a button names, or the incident on a message posted
  # before posts were kept. Returns false when the memory is not one the message shows.
  def decide!(reference:, memory_id:, member:, confirmed:, channel_id:, message_id:)
    post = post_for(reference, channel_id: channel_id, message_id: message_id)
    memory = post && visible(post, member).find { |each| each.id == memory_id }
    return false unless memory

    if confirmed
      memory.confirm!(by: member)
    else
      memory.reject!(by: member, reason: "Marked not right in #{post.incident.identifier}")
    end
    redraw(post)
    true
  end

  # The memory a Correct button names, as the form asking what is right instead shows it, or nil when the message does
  # not show it.
  def correctable(post_id:, memory_id:)
    post = Chat::MemoryPost.find_by(workspace: @workspace, id: post_id)
    post && shown(post).memories.find { |memory| memory.id == memory_id }
  end

  # Someone writing what is right instead. Returns why it was refused, or nil once the correction replaced it.
  def correct!(post_id:, memory_id:, member:, correction:, reason:)
    post = Chat::MemoryPost.find_by(workspace: @workspace, id: post_id)
    memory = post && visible(post, member).find { |each| each.id == memory_id }
    return "That memory is gone. Close this and look on the Memory page." unless memory
    return "Write what is right instead." if correction.blank?

    replacement = memory.reject!(by: member, reason: reason.presence || "Corrected in #{post.incident.identifier}", correction: correction.strip)
    return memory.reject_blocked_reason unless replacement

    redraw(post)
    nil
  rescue ActiveRecord::RecordInvalid => error
    error.record.errors.full_messages.to_sentence
  end

  def shown(post)
    memories = post.memories.map do |memory|
      ShownMemory.new(id: memory.id, text: memory.text, about: memory.about, about_removed: memory.about_removed?, state: memory.state,
                      reason: memory.state_reason, decided_by: (memory.decider if [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_REJECTED ].include?(memory.state)),
                      correction: memory.replaced_by&.text)
    end
    Shown.new(post_id: post.id, kind: post.kind, incident_identifier: post.incident.identifier, memories: memories)
  end

  private

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
