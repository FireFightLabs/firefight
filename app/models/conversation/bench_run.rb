# One pass of the chat bench on one version of Halon and one model. Every scenario, or one real chat, is replayed and
# scored, so two runs can be set side by side to see whether a change to Halon made it better or worse.
class Conversation::BenchRun < ApplicationRecord
  self.table_name = "conversation_bench_runs"

  # The scenarios written from real failures, kept in this repository with no customer data.
  KIND_SCENARIOS = "scenarios"
  # One real chat, replayed from its record in its own workspace.
  KIND_CHAT = "chat"
  KINDS = [ KIND_SCENARIOS, KIND_CHAT ].freeze

  TRIGGER_OPERATOR = "operator"
  TRIGGER_TERMINAL = "terminal"
  TRIGGER_CI = "ci"
  TRIGGERS = [ TRIGGER_OPERATOR, TRIGGER_TERMINAL, TRIGGER_CI ].freeze

  STATUS_RUNNING = "running"
  STATUS_FINISHED = "finished"
  STATUSES = [ STATUS_RUNNING, STATUS_FINISHED ].freeze

  # Every scenario is replayed this many times, so one lucky or unlucky replay is told from a real change. Each repeat is
  # a whole chat on the model, so more cost more.
  DEFAULT_REPEATS = 3
  REPEATS = (1..5)
  # What a run may spend on Halon's calls and the judge's together before it stops, in micros, unless told otherwise.
  DEFAULT_BUDGET_MICROS = 2_000_000
  MICROS_PER_DOLLAR = 1_000_000
  # Repeats of one scenario agree when their totals lie this close, which is how far apart one replay's two readings of
  # the same chat can fairly land.
  AGREEMENT = 0.1

  belongs_to :started_by, class_name: "User", optional: true
  has_many :results, class_name: "Conversation::BenchResult", dependent: :destroy, inverse_of: :bench_run

  validates :kind, inclusion: { in: KINDS }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }
  validates :prompt_version, :model, presence: true
  validate :repeats_and_budget_possible

  scope :recent, -> { order(created_at: :desc) }
  scope :of_scenarios, -> { where(kind: KIND_SCENARIOS) }

  # Runs going at once, across the console, the terminal and CI. Each holds database connections on a server shared
  # with everything else, so a further run waits.
  AT_ONCE = 3
  BUSY = "Three bench runs are already going. Start another once one finishes.".freeze

  def running? = status == STATUS_RUNNING

  # A run whose worker died still reads as running until its scenarios are settled as lost, so only recent runs count.
  def self.busy_reason
    BUSY if where(status: STATUS_RUNNING, created_at: Conversation::BenchResult::STALE_AFTER.ago..).count >= AT_ONCE
  end

  def stopped? = stopped_reason.present?

  # Every model call the run paid for, Halon's and the judge's, from the inference ledger.
  def spent_micros_with_judge
    Inference.where(inferable_type: Conversation::BenchResult.name, inferable_id: results.select(:id)).sum(:cost_micros)
  end

  # What is left of the budget, nil for a run with none.
  def budget_left_micros = budget_micros && [ budget_micros - spent_micros_with_judge, 0 ].max

  def over_budget? = budget_micros.present? && budget_left_micros.zero?

  def budget_reason
    "The run reached its budget of #{budget_words}, so the replays after that point were not run or judged. What scored before it stands."
  end

  def budget_words = budget_micros && format("$%.2f", budget_micros / MICROS_PER_DOLLAR.to_f)

  def stopped_at_budget? = budget_micros.present? && stopped_reason == budget_reason

  # Stops the run once, in one statement, so the first scenario to see the account refused, or the budget spent, says why.
  def stop!(reason)
    self.class.where(id: id, stopped_reason: nil).update_all(stopped_reason: reason, updated_at: Time.current)
    reload
  end

  # Finishes once no scenario is left pending, in one statement, so the last two ending together finish it once.
  def finish_if_done!
    pending = Conversation::BenchResult.where(bench_run_id: id, status: Conversation::BenchResult::STATUS_PENDING).select(:id)
    won = self.class.where(id: id, status: STATUS_RUNNING).where.not(Conversation::BenchResult.where(id: pending).arel.exists)
                    .update_all(status: STATUS_FINISHED, finished_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  private

  def repeats_and_budget_possible
    errors.add(:base, "Each scenario is replayed from #{REPEATS.min} to #{REPEATS.max} times") unless REPEATS.include?(repeats)
    errors.add(:base, "The budget must be more than nothing") if budget_micros && !budget_micros.positive?
  end
end
