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

  belongs_to :started_by, class_name: "User", optional: true
  has_many :results, class_name: "Conversation::BenchResult", dependent: :destroy, inverse_of: :bench_run

  validates :kind, inclusion: { in: KINDS }
  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }
  validates :prompt_version, :model, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :of_scenarios, -> { where(kind: KIND_SCENARIOS) }

  def running? = status == STATUS_RUNNING

  # Finishes once no scenario is left pending, in one statement, so the last two ending together finish it once.
  def finish_if_done!
    pending = Conversation::BenchResult.where(bench_run_id: id, status: Conversation::BenchResult::STATUS_PENDING).select(:id)
    won = self.class.where(id: id, status: STATUS_RUNNING).where.not(Conversation::BenchResult.where(id: pending).arel.exists)
                    .update_all(status: STATUS_FINISHED, finished_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end
end
