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

  # Whether principal may see every memory tonight's run checked, so its run, which reads about all of them, may open for
  # them. One about a resource outside their map reach keeps the run closed to them.
  def visible_to?(principal)
    Chat::Memory.visible_to(principal, workspace).where(id: memory_ids).count == memory_ids.uniq.size
  end

  # The runs of these reviews that principal may open, by id.
  def self.runs_visible_to(principal, run_ids)
    runs = Investigation.where(id: run_ids, subject_type: name).includes(:subject)
    runs.select { |run| run.subject.visible_to?(principal) }.map(&:id).to_set
  end

  # The run checking tonight's memories, which each line of history Halon writes links to.
  def run = investigations.order(:created_at).last

  def settled?(memory) = settled_ids.include?(memory.id)

  # One more memory merged tonight, counted in one statement.
  def count_merge! = self.class.where(id: id).update_all("merged = merged + 1")

  # A removal taken for a change that did not happen, such as a merge refused or decided on meanwhile, is given back.
  def give_back_removal!
    self.class.where(id: id).where("removals > 0").update_all("removals = removals - 1")
    reload
  end

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
    else memory.unsettled_by_halon!(note: evidence, review: self)
    end
    release!(memory) unless settled.outcome
    settled
  rescue StandardError
    release!(memory)
    raise
  end

  # The run ended, so what it never settled is kept as it is, with a line in its history. Its last check is left alone,
  # so it keeps its place in the queue for the next night. Only once.
  def finish!
    return false unless self.class.where(id: id, finished_at: nil).update_all(finished_at: Time.current, updated_at: Time.current) > 0

    reload
    memories.reject { |memory| settled?(memory) }.each { |memory| memory.not_reached_by_halon!(review: self) }
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
