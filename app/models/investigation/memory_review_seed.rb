# The facts for a night's memory check: each memory picked for tonight, what it is about, who stands behind it, and what
# Halon found the last time it checked it. A memory a person decided on says so, with the evidence they decided after,
# so the run raises only what they have not seen. The memories go in the run's encrypted notes (to_check), never in its
# plain facts.
class Investigation::MemoryReviewSeed
  def initialize(investigation)
    @investigation = investigation
    @review = investigation.memory_review
  end

  def gather
    {
      Investigation::Seeding::KEY_GATHERED_AT => Time.current.iso8601,
      "today" => Date.current.iso8601,
      "how_many" => @review.memory_ids.size
    }
  end

  def to_check = @review.memories.map { |memory| facts(memory) }

  private

  def facts(memory)
    {
      "id" => memory.id, "fact" => memory.text, "about" => about(memory), "state" => memory.state, "stands_behind" => behind(memory),
      "why_disputed" => (memory.state_reason if memory.state == Chat::Memory::STATE_DISPUTED),
      "why_rejected" => (memory.state_reason if memory.rejected_by_halon?),
      "says_otherwise_than" => partners(memory).presence,
      "last_checked" => last_checked(memory)
    }.compact
  end

  def about(memory)
    return "the whole workspace" unless memory.subject
    return "#{memory.subject.name} (resource #{memory.subject.id} on the map#{', no longer on the map' if memory.about_removed?})" if memory.subject.is_a?(ResourceMap::Resource)

    "#{memory.subject.name} (catalog entry #{memory.subject.id})"
  end

  # Who decided, and when, so a person's decision is never read as Halon's.
  def behind(memory)
    return "#{memory.confirmed_by.display_name}, a person, confirmed it on #{memory.confirmed_at.to_date.iso8601}" if memory.confirmed_by && memory.confirmed_at
    return "a completed postmortem confirmed it" if memory.confirmed? && memory.decided_by_postmortem_id
    return "you confirmed it on an earlier night" if memory.confirmed? && memory.decided_by_halon
    if memory.rejected_by_halon?
      return "you rejected it on #{memory.rejected_at&.to_date&.iso8601 || 'an earlier night'}. Check whether it holds now, since production may have changed"
    end

    "nobody yet"
  end

  def partners(memory)
    memory.contradiction_partners.map { |partner| { "id" => partner.id, "fact" => partner.text, "state" => partner.state } }
  end

  def last_checked(memory)
    return nil unless memory.checked_at

    last = memory.events.reverse.find { |event| event.actor == Chat::MemoryEvent::ACTOR_HALON && event.detail.present? }
    { "on" => memory.checked_at.to_date.iso8601, "came_to" => memory.check_outcome, "found" => last&.detail }.compact
  end
end
