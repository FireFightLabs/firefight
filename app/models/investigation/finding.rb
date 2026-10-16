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

  # What kind of answer it is, as the agent judged it when it concluded.
  KIND_ROOT_CAUSE = "root_cause".freeze
  KIND_LIKELY_CAUSE = "likely_cause".freeze
  KIND_NO_CAUSE = "no_cause".freeze
  KINDS = [ KIND_ROOT_CAUSE, KIND_LIKELY_CAUSE, KIND_NO_CAUSE ].freeze
  HEADLINES = { KIND_ROOT_CAUSE => "Root cause found", KIND_LIKELY_CAUSE => "Likely cause", KIND_NO_CAUSE => "No cause found yet" }.freeze
  # A root cause is said to be found only when the agent is this sure of it. Below, it is a likely cause.
  FOUND_AT = 0.7
  # How sure the agent is, from the most sure down, in the words a responder reads.
  SURENESS = [ [ 0.85, "Very sure" ], [ 0.6, "Fairly sure" ], [ 0.35, "Not very sure" ], [ 0, "A guess" ] ].freeze
  # The short answer cites this many claims at most, and the rest are in the full answer.
  SHORT_EVIDENCE = 3

  belongs_to :investigation
  belongs_to :winning_hypothesis, class_name: "Investigation::Hypothesis", optional: true
  belongs_to :outcome_by, polymorphic: true, optional: true
  # Whoever a run an alert started found on call, whom Firefight pages with the answer (Investigation::Paging), and the
  # on-call tool and target the page goes to when one is connected. page_email is who the tool named, member or not.
  belongs_to :page_member, class_name: "WorkspaceMembership", optional: true
  belongs_to :page_integration, class_name: "Integration", optional: true
  scope :in_workspace, ->(workspace) {
    joins(:investigation).where(investigations: { workspace_id: workspace.id })
  }

  has_many :evidence_items, -> { ordered }, class_name: "Investigation::Evidence", dependent: :destroy, inverse_of: :finding
  # The fix and, once written, its undo, which is what a run's fix endpoints act on.
  def plans = [ remediation_plan, remediation_plan&.undo_plan ].compact

  has_many :verdicts, class_name: "Investigation::Verdict", dependent: :destroy, inverse_of: :finding
  # The fix. An undo of it is a plan on the same finding, reached through the fix.
  has_one :remediation_plan, -> { where(undoes_id: nil) }, class_name: "Investigation::RemediationPlan", dependent: :destroy, inverse_of: :finding

  # The answer as every reader but the dashboard takes it, Slack, MCP, the timeline, search and other prompts among them,
  # without the markers that place the run's charts (Chat::Chart::Marker). placed_summary keeps them.
  def summary = Chat::Chart::Marker.strip(super)

  def gaps = Chat::Chart::Marker.strip(super)

  def placed_summary = self[:summary]

  validates :published_state, inclusion: { in: STATES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true
  validates :answer_kind, inclusion: { in: KINDS }, allow_nil: true

  # The kind the short answer leads with. A root cause the agent is not sure of reads as a likely one, and an answer
  # written before kinds were asked for is read from whether it named a cause.
  def shown_kind
    kind = answer_kind || (winning_hypothesis_id ? KIND_LIKELY_CAUSE : KIND_NO_CAUSE)
    kind == KIND_ROOT_CAUSE && confidence && confidence < FOUND_AT ? KIND_LIKELY_CAUSE : kind
  end

  def headline = HEADLINES.fetch(shown_kind)

  # How sure the agent is, in words, or nil for an answer with no cause or no confidence given.
  def sureness
    return nil if confidence.nil? || shown_kind == KIND_NO_CAUSE

    SURENESS.find { |floor, _words| confidence >= floor }&.last
  end

  # What is wrong in one plain sentence. An answer written before it was asked for gives its summary's first sentence.
  def what_is_wrong_line = what_is_wrong.presence || summary.to_s.split(/(?<=[.!?])\s/).first.to_s.strip

  # The claims the short answer cites, each in plain words where the agent gave them.
  def short_evidence = evidence_items.first(SHORT_EVIDENCE).map { |item| item.plain.presence || item.claim }

  def suggested_fix_line = suggested_fix.presence || remediation_plan&.summary

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
    won = self.class.where(id: id, paged_at: nil).where("page_member_id IS NOT NULL OR page_integration_id IS NOT NULL")
                    .update_all(paged_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  def add_evidence!(claim:, sources:, position:, plain: nil)
    item = evidence_items.create!(claim: claim, plain: plain, position: position)
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
