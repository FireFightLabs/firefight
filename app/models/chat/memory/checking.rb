# Halon checking a memory against production, every night, as the investigator. What it shows right counts as confirmed
# by Halon, with the evidence and the date kept. What it shows wrong is corrected or rejected with the evidence, and what
# it cannot tell either way is kept, with when it was last tried. A person's own decision always outranks Halon's. What a
# person confirmed is never rejected or corrected by Halon, only disputed for them when Halon found something they had
# not seen. Removals are held to a share of the workspace's memories each night (Chat::MemoryReview#take_removal!).
module Chat::Memory::Checking
  extend ActiveSupport::Concern

  VERDICT_RIGHT = "right".freeze
  VERDICT_WRONG = "wrong".freeze
  VERDICT_UNSURE = "unsure".freeze
  VERDICTS = [ VERDICT_RIGHT, VERDICT_WRONG, VERDICT_UNSURE ].freeze
  # Shown wrong, but tonight's limit on removals was reached, so it was left as it was.
  OUTCOME_HELD = "held".freeze
  OUTCOMES = (VERDICTS + [ OUTCOME_HELD ]).freeze

  # What Halon checks: what it uses, and what is disputed and waits to be settled. What a person or Halon rejected, what
  # expired and what was merged are left alone.
  CHECKED_STATES = [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED ].freeze
  NIGHTLY_LIMIT = 25
  # At most this share of the workspace's memories in use is rejected or merged in one night, and never fewer than the floor.
  REMOVAL_SHARE = 0.15
  REMOVAL_FLOOR = 3

  # How a memory stands, as the Memory page says it.
  STANDING_PERSON = "person".freeze
  STANDING_POSTMORTEM = "postmortem".freeze
  STANDING_HALON = "halon".freeze
  STANDING_UNCHECKED = "unchecked".freeze
  STANDINGS = [ STANDING_PERSON, STANDING_POSTMORTEM, STANDING_HALON, STANDING_UNCHECKED ].freeze

  # What a check came to, and the words the agent reads back.
  Settled = Data.define(:outcome, :words)

  included do
    validates :check_outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  end

  class_methods do
    # Tonight's memories to check, picked in code: changed since Halon last checked them first, then never checked, then
    # checked longest ago.
    def to_check(workspace, limit: NIGHTLY_LIMIT)
      where(workspace: workspace, state: CHECKED_STATES)
        .order(Arel.sql("CASE WHEN checked_at IS NOT NULL AND updated_at > checked_at THEN 0 WHEN checked_at IS NULL THEN 1 ELSE 2 END"),
               Arel.sql("checked_at ASC NULLS FIRST"), :created_at, :id)
        .limit(limit)
    end

    # How many memories one night may reject or merge.
    def removal_cap(workspace)
      [ (in_use.where(workspace: workspace).count * REMOVAL_SHARE).floor, REMOVAL_FLOOR ].max
    end
  end

  # Waiting on a person, when two memories say otherwise and Halon could not settle which is right, or when Halon found
  # evidence against what a person decided. Either way Halon has tried since it was disputed.
  def awaiting_decision?
    state == Chat::Memory::STATE_DISPUTED && checked_at.present? && checked_at >= updated_at && (confirmed_by_id.present? || contradicted_by_id.present?)
  end

  # How it stands, or nil when it is not in use and its state says it all.
  def standing
    return nil unless in_use?
    return STANDING_PERSON if confirmed_by_id
    return STANDING_POSTMORTEM if confirmed? && decided_by_postmortem_id
    return STANDING_HALON if confirmed? && decided_by_halon

    STANDING_UNCHECKED
  end

  # A person stands behind it, so Halon never overturns it.
  def person_stands_behind? = confirmed_by_id.present? && [ Chat::Memory::STATE_CONFIRMED, Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED ].include?(state)

  # Production shows it holds. What Halon or nobody stood behind becomes confirmed by Halon. A person's confirmation stays
  # theirs, with Halon's check kept beside it. A memory it disputed, or that disputed it, is settled against it.
  def verified_by_halon!(evidence:, review:)
    transaction do
      settled = if confirmed?
        # Halon's own confirmation is dated from the check that last showed it right.
        update_columns(checked_at: Time.current, check_outcome: VERDICT_RIGHT, **({ confirmed_at: Time.current } if decided_by_halon && confirmed_by_id.nil?).to_h)
      else
        person = confirmed_by_id.present?
        decide!(Chat::Memory::STATE_CONFIRMED, from: [ Chat::Memory::STATE_UNCONFIRMED, Chat::Memory::STATE_OUTDATED, Chat::Memory::STATE_DISPUTED ],
                checked: VERDICT_RIGHT, decided_by_halon: !person, state_reason: nil, confirmed_at: person ? confirmed_at : Time.current,
                decided_by_postmortem_id: (decided_by_postmortem_id if person))
      end
      next Settled.new(outcome: nil, words: "It changed while you checked it. Leave it for tonight.") unless settled

      record!(Chat::MemoryEvent::KIND_VERIFIED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: evidence)
      partners = contradiction_partners.map { |partner| partner.settle_against!(self, evidence, review) }.compact
      Settled.new(outcome: VERDICT_RIGHT, words: [ person_stands_behind? ? "Recorded. A person confirmed it, and your check is kept beside theirs." : "Confirmed by your check.", *partners ].join(" "))
    end
  end

  # Production shows it does not hold. A person's memory is disputed for them, only with evidence they have not seen. Any
  # other is corrected when Halon knows what is right instead, or rejected, while tonight's removals allow.
  def found_wrong_by_halon!(evidence:, correction:, review:)
    return disputed_for_person!(evidence) if person_stands_behind?

    transaction do
      next held!(evidence) unless review.take_removal!

      replacement = correction.present? ? halon_correction(correction, evidence) : nil
      moved = decide!(Chat::Memory::STATE_REJECTED, from: Chat::Memory::REJECTABLE_FROM, checked: VERDICT_WRONG, decided_by_halon: true,
                      state_reason: evidence, rejected_by_id: nil, rejected_at: Time.current, decided_by_postmortem_id: nil, replaced_by_id: replacement&.id)
      raise ActiveRecord::Rollback unless moved

      record!(replacement ? Chat::MemoryEvent::KIND_CORRECTED : Chat::MemoryEvent::KIND_REJECTED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: evidence)
      Settled.new(outcome: VERDICT_WRONG, words: replacement ? "Corrected. Halon now remembers \"#{replacement.text}\" instead." : "Rejected, so it is no longer used.")
    end || Settled.new(outcome: nil, words: "It changed while you checked it. Leave it for tonight.")
  end

  # Neither shown right nor wrong. It keeps its state, marked as tried now. The time it last changed is left alone, so
  # trying it never counts as a change.
  def unsettled_by_halon!(note:)
    update_columns(checked_at: Time.current, check_outcome: VERDICT_UNSURE)
    record!(Chat::MemoryEvent::KIND_UNSETTLED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: note)
    Settled.new(outcome: VERDICT_UNSURE, words: "Kept as it is, marked as not checked yet.")
  end

  # The evidence Halon last showed it right with, and when, read from its history.
  def last_verified
    events.select { |event| event.kind == Chat::MemoryEvent::KIND_VERIFIED }.max_by(&:created_at)
  end

  # The memories this one says otherwise than: the newer one that disputed it, and those it disputed.
  def contradiction_partners
    [ contradicted_by, *self.class.where(contradicted_by_id: id, state: Chat::Memory::STATE_DISPUTED).to_a ].compact.uniq
  end

  protected

  # winner was shown right and says otherwise than this one. One a person stands behind is disputed for them with the
  # evidence. Any other is rejected, as the one it said otherwise than, while tonight's removals allow. Returns what
  # became of it in words, or nil when nothing did.
  def settle_against!(winner, evidence, review)
    reason = "Halon checked \"#{winner.text}\" against production and it holds. #{evidence}"
    if person_stands_behind?
      return nil if state == Chat::Memory::STATE_DISPUTED && !new_evidence?(evidence)

      disputed = state == Chat::Memory::STATE_DISPUTED ? touch_dispute!(reason) : dispute!(reason, checked: VERDICT_WRONG)
      return disputed ? "Memory #{id} says otherwise and a person confirmed it, so it is disputed for them to decide." : nil
    end
    return nil unless Chat::Memory::REJECTABLE_FROM.include?(state)
    return (held!(reason) && "Memory #{id} says otherwise, but tonight's limit on removals is reached, so it is left for another night.") unless review.take_removal!

    return nil unless decide!(Chat::Memory::STATE_REJECTED, from: Chat::Memory::REJECTABLE_FROM, checked: VERDICT_WRONG, decided_by_halon: true,
                              state_reason: reason, rejected_by_id: nil, rejected_at: Time.current, decided_by_postmortem_id: nil, replaced_by_id: winner.id)

    record!(Chat::MemoryEvent::KIND_REJECTED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: reason)
    "Memory #{id} said otherwise, so it is rejected."
  end

  private

  # Halon found evidence against what a person decided. It is raised as a dispute, which waits on a person, and only
  # with evidence Halon had not already raised before they decided.
  def disputed_for_person!(evidence)
    return held_for_person!(evidence) unless new_evidence?(evidence)

    reason = "Halon checked it against production on #{Date.current.iso8601} and found otherwise. #{evidence}"
    moved = state == Chat::Memory::STATE_DISPUTED ? touch_dispute!(reason) : dispute!(reason, checked: VERDICT_WRONG)
    return Settled.new(outcome: nil, words: "It changed while you checked it. Leave it for tonight.") unless moved

    Settled.new(outcome: VERDICT_WRONG, words: "A person confirmed it, so it is not changed. It is disputed with your evidence for them to decide.")
  end

  def held_for_person!(evidence)
    update_columns(checked_at: Time.current, check_outcome: OUTCOME_HELD)
    record!(Chat::MemoryEvent::KIND_HELD, actor: Chat::MemoryEvent::ACTOR_HALON, detail: evidence)
    Settled.new(outcome: OUTCOME_HELD, words: "A person kept it after seeing this evidence, so it is left as they decided.")
  end

  # A person decided after Halon raised the same evidence, so raising it again would overturn them without anything new.
  def new_evidence?(evidence)
    decided_at = [ confirmed_at, rejected_at ].compact.max
    return true unless decided_at

    seen = events.select do |event|
      event.actor == Chat::MemoryEvent::ACTOR_HALON && event.created_at <= decided_at &&
        [ Chat::MemoryEvent::KIND_DISPUTED, Chat::MemoryEvent::KIND_HELD ].include?(event.kind)
    end
    said = Chat::Memory::Words.stems(evidence, skip: Chat::Memory::Words::FILLER).uniq
    seen.none? { |event| (said - Chat::Memory::Words.stems(event.detail.to_s, skip: Chat::Memory::Words::FILLER)).empty? }
  end

  # Already disputed and waiting, so the newer evidence takes the old reason's place and it is marked as tried now.
  def touch_dispute!(reason)
    now = Time.current
    moved = self.class.where(id: id, state: Chat::Memory::STATE_DISPUTED)
                      .update_all(state_reason: reason, checked_at: now, check_outcome: VERDICT_WRONG, updated_at: now) > 0
    reload
    record!(Chat::MemoryEvent::KIND_DISPUTED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: reason) if moved
    moved
  end

  def held!(evidence)
    update_columns(checked_at: Time.current, check_outcome: OUTCOME_HELD)
    record!(Chat::MemoryEvent::KIND_HELD, actor: Chat::MemoryEvent::ACTOR_HALON, detail: evidence)
    Settled.new(outcome: OUTCOME_HELD, words: "Tonight's limit on removing memories is reached, so it is left as it is and checked again on a later night.")
  end

  # What is right instead, as Halon checked it, saved as confirmed by Halon with the same evidence. Screened like
  # anything Halon learns, so a live value or a fact about a person is refused with why.
  def halon_correction(correction, evidence)
    refusal = Chat::Memory::Screening.refusal(workspace, Chat::SecretFree.redacted(correction))
    raise Chat::Memory::Refused, refusal if refusal

    now = Time.current
    self.class.create!(workspace: workspace, text: correction, subject: subject, source: source, state: Chat::Memory::STATE_CONFIRMED,
                       decided_by_halon: true, confirmed_at: now, checked_at: now, check_outcome: VERDICT_RIGHT, created_at: now, updated_at: now).tap do |replacement|
      replacement.record!(Chat::MemoryEvent::KIND_LEARNED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: "It corrected \"#{text}\".")
      replacement.record!(Chat::MemoryEvent::KIND_VERIFIED, actor: Chat::MemoryEvent::ACTOR_HALON, detail: evidence)
    end
  end
end
