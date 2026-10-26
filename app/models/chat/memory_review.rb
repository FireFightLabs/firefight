# One night's check of a workspace's memories: which ones it picked, in code, which it settled, and how many it may still
# reject or merge. It is the subject of the run that checks them, so a workspace never has two at once, and each night
# has at most one.
class Chat::MemoryReview < ApplicationRecord
  self.table_name = "chat_memory_reviews"

  # Said of a memory the run never got to, such as one it ran out of time or budget before.
  NOT_REACHED = "Halon did not get to it before tonight's check ended.".freeze

  belongs_to :workspace
  has_many :investigations, as: :subject, dependent: :restrict_with_exception

  validates :reviewed_on, uniqueness: { scope: :workspace_id }
  validates :removal_cap, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Tonight's review, or nil when this night already has one.
  def self.open!(workspace, on: Date.current)
    create!(workspace: workspace, reviewed_on: on, removal_cap: Chat::Memory.removal_cap(workspace))
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil
  end

  # What the run checks, in the order picked.
  def memories
    found = Chat::Memory.where(workspace_id: workspace_id, id: memory_ids).includes(:subject, :confirmed_by, :events).index_by(&:id)
    memory_ids.filter_map { |id| found[id] }
  end

  def picked!(memories) = update!(memory_ids: memories.map(&:id))

  def settled?(memory) = settled_ids.include?(memory.id)

  # The run's answer, in counts only, so no memory's words are kept outside the memory.
  def summary
    left = memory_ids.size - settled_ids.size
    [ "Checked #{settled_ids.size} of #{memory_ids.size} #{memory_ids.size == 1 ? 'memory' : 'memories'} against production.",
      ("#{left} not reached, kept as not checked." if left.positive?),
      ("Merged #{merged} that said the same as another." if merged.positive?) ].compact.join(" ")
  end

  # Takes one of tonight's removals, or answers false once they are spent. One statement, so two settles at once never
  # both take the last.
  def take_removal!
    taken = self.class.where(id: id).where("removals < removal_cap").update_all("removals = removals + 1") > 0
    reload if taken
    taken
  end

  # What Halon's check of one picked memory came to, said back to the agent. Each memory is settled once a night.
  def settle!(memory, verdict:, evidence:, correction: nil)
    return Chat::Memory::Settled.new(outcome: nil, words: "Memory #{memory.id} is not one of tonight's.") unless memory_ids.include?(memory.id)
    return Chat::Memory::Settled.new(outcome: nil, words: "Memory #{memory.id} was settled already tonight.") unless claim!(memory)

    settled = case verdict
    when Chat::Memory::VERDICT_RIGHT then memory.verified_by_halon!(evidence: evidence, review: self)
    when Chat::Memory::VERDICT_WRONG then memory.found_wrong_by_halon!(evidence: evidence, correction: correction, review: self)
    else memory.unsettled_by_halon!(note: evidence)
    end
    release!(memory) unless settled.outcome
    settled
  rescue StandardError
    release!(memory)
    raise
  end

  # The run ended, so what it never settled is marked as tried tonight and kept as it is. Only once.
  def finish!
    return false unless self.class.where(id: id, finished_at: nil).update_all(finished_at: Time.current, updated_at: Time.current) > 0

    reload
    memories.reject { |memory| settled?(memory) }.each { |memory| memory.unsettled_by_halon!(note: NOT_REACHED) }
    true
  end

  private

  def claim!(memory)
    claimed = self.class.where(id: id).where.not("? = ANY(settled_ids)", memory.id)
                        .update_all([ "settled_ids = array_append(settled_ids, ?::uuid)", memory.id ]) > 0
    reload
    claimed
  end

  def release!(memory)
    self.class.where(id: id).update_all([ "settled_ids = array_remove(settled_ids, ?::uuid)", memory.id ])
    reload
  end
end
