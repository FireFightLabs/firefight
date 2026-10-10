class Investigation::Finding < ApplicationRecord
  include Investigation::Finding::Searchable
  STATE_UNPUBLISHED = "unpublished"
  STATE_PUBLISHED = "published"
  # Below the workspace's confidence bar, or holding instruction-like evidence.
  STATE_HELD = "held"
  STATES = [ STATE_UNPUBLISHED, STATE_PUBLISHED, STATE_HELD ].freeze

  OUTCOME_CONFIRMED = "confirmed"
  OUTCOME_PARTIAL = "partial"
  OUTCOME_WRONG = "wrong"
  OUTCOMES = [ OUTCOME_CONFIRMED, OUTCOME_PARTIAL, OUTCOME_WRONG ].freeze
  # How a person rating an answer reads each outcome.
  OUTCOME_WORDS = { OUTCOME_CONFIRMED => "right", OUTCOME_PARTIAL => "partly right", OUTCOME_WRONG => "wrong" }.freeze

  belongs_to :investigation
  belongs_to :winning_hypothesis, class_name: "Investigation::Hypothesis", optional: true
  belongs_to :outcome_by, polymorphic: true, optional: true
  # Whoever a run an alert started found on call, whom Firefight pages with the answer (Investigation::Paging).
  belongs_to :page_member, class_name: "WorkspaceMembership", optional: true
  scope :in_workspace, ->(workspace) {
    joins(:investigation).where(investigations: { workspace_id: workspace.id })
  }

  has_many :evidence_items, -> { ordered }, class_name: "Investigation::Evidence", dependent: :destroy, inverse_of: :finding
  # The fix and, once written, its undo, which is what a run's fix endpoints act on.
  def plans = [ remediation_plan, remediation_plan&.undo_plan ].compact

  has_many :verdicts, class_name: "Investigation::Verdict", dependent: :destroy, inverse_of: :finding
  # The fix. An undo of it is a plan on the same finding, reached through the fix.
  has_one :remediation_plan, -> { where(undoes_id: nil) }, class_name: "Investigation::RemediationPlan", dependent: :destroy, inverse_of: :finding

  validates :published_state, inclusion: { in: STATES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  # Answers the team stood by or marked wrong, in workspaces that let Firefight test Halon on them. Only a run that
  # finished can be replayed, since a replay answers every call from what the run read.
  scope :regression_cases, lambda {
    joins(investigation: :workspace)
      .where(outcome: [ OUTCOME_CONFIRMED, OUTCOME_WRONG ], workspaces: { halon_regression_enabled: true })
      .where(investigations: { rehearsal: false, status: Investigation::STATUS_SUCCEEDED })
      .where.not(summary: [ nil, "" ])
      .order(outcome_at: :desc)
  }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  # Everyone who read the finding gets a say, and anyone may change their mind. The outcome the
  # record carries is what the room agreed, or nothing while the room is split. The row is locked
  # first, so two thumbs pressed together tally each other rather than settling on a count that missed one.
  def record_verdict!(outcome, by:)
    with_lock do
      verdict = verdicts.find_or_initialize_by(member: by)
      verdict.outcome = outcome
      verdict.save!
      settle_outcome!
      verdict
    end
  end

  # What the person who rated it is told, wherever they rated it.
  def self.verdict_recorded(outcome) = "Thanks. You rated this answer #{OUTCOME_WORDS.fetch(outcome)}."

  # What a person said about this answer, or nil before they rated it.
  def verdict_of(member)
    return nil unless member.is_a?(WorkspaceMembership)

    verdicts.find { |verdict| verdict.member_id == member.id }&.outcome
  end

  # Claims the one page, so a retried job never pages twice.
  def claim_page!
    won = self.class.where(id: id, paged_at: nil).where.not(page_member_id: nil).update_all(paged_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  def add_evidence!(claim:, sources:, position:)
    item = evidence_items.create!(claim: claim, position: position)
    sources.each { |source| item.citations.create!(source: source) }
    item
  end

  def tally
    verdicts.group(:outcome).count
  end

  private

  def settle_outcome!
    counts = tally
    agreed = counts.size == 1 ? counts.keys.first : nil
    update!(outcome: agreed, outcome_at: agreed ? Time.current : nil, outcome_by: nil)
    relearn_after_mistake if saved_change_to_outcome? && outcome == OUTCOME_WRONG
  end

  # Marked wrong once its incident had ended, so what the mistake taught is learned, and the channel asked to confirm it.
  # Once per answer, claimed in one statement, so a room changing its mind back and forth never asks the model again.
  def relearn_after_mistake
    incident = investigation.incident
    return unless defined?(FirefightAi) && !investigation.rehearsal? && incident&.closed?
    return unless self.class.where(id: id, relearned_at: nil).update_all(relearned_at: Time.current) == 1

    ActiveRecord.after_all_transactions_commit { IncidentMistakeLearningJob.perform_later(incident.id) }
  end
end
