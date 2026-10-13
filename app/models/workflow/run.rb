# One run of a workflow: what started it and with what, the version it ran, who it acted as, and what each step took
# in, gave back and kept. It is the app's own record, kept after the engine prunes its rows, and the engine's moves
# reach it as they happen. Every status change is one guarded update on the statuses it may leave, so a late event
# never moves a finished run back.
class Workflow::Run < ApplicationRecord
  self.table_name = "workflow_runs"

  # Turned down before anything was made, with the sentence that says why.
  class Refused < StandardError; end

  STATUS_QUEUED = "queued".freeze
  STATUS_RUNNING = "running".freeze
  # Parked on a step that waits for a time, an event or a workflow it ran.
  STATUS_WAITING = "waiting".freeze
  # An operator paused it, and it carries on when they resume it.
  STATUS_PAUSED = "paused".freeze
  STATUS_SUCCEEDED = "succeeded".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_CANCELLED = "cancelled".freeze
  STATUSES = [ STATUS_QUEUED, STATUS_RUNNING, STATUS_WAITING, STATUS_PAUSED, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELLED ].freeze
  OPEN = [ STATUS_QUEUED, STATUS_RUNNING, STATUS_WAITING, STATUS_PAUSED ].freeze
  FINISHED = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_CANCELLED ].freeze

  STARTED_BY_PERSON = "person".freeze
  STARTED_BY_HALON = "halon".freeze
  # Its trigger fired, such as a schedule or an event.
  STARTED_BY_TRIGGER = "trigger".freeze
  STARTED_BY_WORKFLOW = "workflow".freeze
  STARTED_BY = [ STARTED_BY_PERSON, STARTED_BY_HALON, STARTED_BY_TRIGGER, STARTED_BY_WORKFLOW ].freeze

  include Workflow::Run::Data
  include Workflow::PrivateInputs
  include Workflow::Run::Progress
  include Workflow::Run::Retention
  include Workflow::Run::Acting
  include Workflow::Run::Testing

  belongs_to :workspace
  belongs_to :workflow, inverse_of: :runs
  belongs_to :version, class_name: "Workflow::Version"
  belongs_to :parent_run, class_name: "Workflow::Run", optional: true
  # The workflow's own identity it acted as, kept as it was when the run started.
  belongs_to :agent, optional: true
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  # The run this one started again from a later step, taking its results for the steps before that step.
  belongs_to :rerun_of, class_name: "Workflow::Run", optional: true
  has_many :steps, -> { order(:created_at, :iteration) }, class_name: "Workflow::Run::Step", foreign_key: :run_id, inverse_of: :run
  has_many :child_runs, class_name: "Workflow::Run", foreign_key: :parent_run_id, inverse_of: :parent_run
  has_many :saved_results, class_name: "Chat::SavedResult", foreign_key: :workflow_run_id, inverse_of: :workflow_run
  # Every call its steps made, as the activity log keeps them.
  has_many :invocations, class_name: "Ability::Invocation", foreign_key: :workflow_run_id, inverse_of: :workflow_run
  has_many :notices, class_name: "Investigation::Notice", foreign_key: :workflow_run_id, inverse_of: :workflow_run

  validates :status, inclusion: { in: STATUSES }
  validates :trigger_kind, inclusion: { in: Workflow::Trigger::KINDS }
  validates :started_by_kind, inclusion: { in: STARTED_BY }
  validates :start_key, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :unfinished, -> { where(status: OPEN) }
  scope :real, -> { where(test: false) }

  def finished? = FINISHED.include?(status)
  def failed? = status == STATUS_FAILED
  def succeeded? = status == STATUS_SUCCEEDED

  def cancel_blocked_reason
    return "This run has already ended." if finished?

    nil
  end

  # Ends it with every step still going. A run that ended meanwhile stays as it ended.
  def cancel!(by:)
    blocked = cancel_blocked_reason
    raise Refused, blocked if blocked
    raise Refused, cancel_blocked_reason || "This run could not be stopped." unless DefinedWorkflow.cancel!(self, by: by)

    reload
  end

  def pin_blocked_reason
    "Its details were already dropped, so there is nothing left to keep." if details_pruned?
  end

  # A pinned run keeps its details past the workspace's retention.
  def pin!(pinned)
    blocked = pinned && pin_blocked_reason
    raise Refused, blocked if blocked

    self.class.where(id: id, details_pruned_at: nil).update_all(pinned: pinned, updated_at: Time.current)
    reload
  end

  # Takes telling people how it ended, once, so a run told already is never told again.
  def claim_telling!
    self.class.where(id: id, told_at: nil, status: FINISHED).update_all(told_at: Time.current, updated_at: Time.current) == 1
  end

  # The one run a start key names, made the first time it is asked for. Returns the run and whether it is new.
  def self.open!(workflow:, start_key:, **attributes)
    existing = workflow.runs.find_by(start_key: start_key)
    return [ existing, false ] if existing

    run = transaction(requires_new: true) { workflow.runs.create!(attributes.merge(workspace: workflow.workspace, start_key: start_key)) }
    [ run, true ]
  rescue ActiveRecord::RecordNotUnique
    [ workflow.runs.find_by!(start_key: start_key), false ]
  end

  # Whether the engine may move it now. Without the workflows flag nothing starts, waits out its time or carries on.
  def may_move? = FeatureFlags.enabled?(workspace, FeatureFlags::WORKFLOWS)

  def move!(to:, from:, **columns)
    moved = self.class.where(id: id, status: from).update_all(columns.merge(status: to, updated_at: Time.current)) == 1
    reload if moved
    moved
  end
end
