# One scenario, or one real chat, replayed in a bench run, with how it scored. It owns the replay's chat with the model,
# which nobody in the workspace sees.
class Conversation::BenchResult < ApplicationRecord
  self.table_name = "conversation_bench_results"

  STATUS_PENDING = "pending"
  STATUS_SCORED = "scored"
  # The replay could not finish, which says nothing about Halon either way.
  STATUS_ERRORED = "errored"
  STATUSES = [ STATUS_PENDING, STATUS_SCORED, STATUS_ERRORED ].freeze
  # Longer than any replay is allowed to run, so a scenario still pending this long after it was started, or after it
  # was made and never started, has lost its worker or its job.
  STALE_AFTER = 2.hours

  # A real chat's replay says what the customer's systems returned, so what it answered is kept like the chat itself.
  encrypts :answer, :reason

  belongs_to :bench_run, class_name: "Conversation::BenchRun", inverse_of: :results
  belongs_to :workspace
  belongs_to :replay_of, class_name: "Conversation", optional: true
  has_one :chat, as: :owner, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :scenario, :title, presence: true

  scope :scored, -> { where(status: STATUS_SCORED) }
  scope :stale, lambda {
    pending = where(status: STATUS_PENDING)
    pending.where(started_at: ...STALE_AFTER.ago).or(pending.where(started_at: nil, created_at: ...STALE_AFTER.ago))
  }

  def score
    Conversation::BenchScore.new(right: right, moved_forward: moved_forward, asked_when_needed: asked_when_needed, cost: cost)
  end

  # Starts the replay once, so a retried job never runs and pays for the same scenario twice.
  def claim!
    won = self.class.where(id: id, status: STATUS_PENDING, started_at: nil).update_all(started_at: Time.current, updated_at: Time.current)
    reload
    won == 1
  end

  # Settles a pending scenario once, so a retried job never overwrites what an earlier attempt decided.
  def settle!(status:, **columns)
    won = self.class.where(id: id, status: STATUS_PENDING).update_all(status: status, finished_at: Time.current, updated_at: Time.current, **columns)
    reload
    won == 1
  end

  # A replay's chat keeps what the person and Halon said and puts the work in between away, like a conversation's.
  def keeps_in_memory?(message)
    Chat::Message::READABLE_ROLES.include?(message.role) && !message.nudge && message.ruby_llm_tool_calls.empty?
  end

  def memory_brief = nil
end
