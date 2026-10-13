# What every kind of step shares. The class side describes the kind, which publishing, the pages and Halon read. An
# instance runs one step of one run: it is handed the run's record, the engine's step and the step's config already
# filled from the run's data, and answers the step's output, or parks the step while something it asked for happens.
#
# A step that changes something goes through the same rules wherever it runs: a test run only pretends unless the
# person testing turned that step on, a freeze window stops it or makes it wait, and a run nobody pressed reads how
# things stand first and stops if they moved.
class DefinedWorkflow::Steps::Base
  GROUP_HALON = "halon".freeze
  GROUP_TOOLS = "tools".freeze
  GROUP_MESSAGES = "messages".freeze
  GROUP_WAITING = "waiting".freeze
  GROUP_CONTROL = "control".freeze
  GROUPS = [ GROUP_HALON, GROUP_TOOLS, GROUP_MESSAGES, GROUP_WAITING, GROUP_CONTROL ].freeze

  # Why a step cannot go on, in words. Running it again gives the same answer, so it is never retried.
  class Refused < StandardError; end
  # What the step called answered with a failure. It is tried again only when the step asks for retries.
  class Failed < StandardError; end

  KEY_UNDO = "undo".freeze
  OUTPUT_SIMULATED = "simulated".freeze
  OUTPUT_WOULD = "would".freeze
  CHECKPOINT_ASKED = "asked".freeze
  CHECKPOINT_DELIVERED = "delivered".freeze
  # How long a step waits for work it handed off, such as Halon reading, when the step sets no time limit of its own.
  HANDED_OFF_LIMIT = 30.minutes
  # What a step that reads how things stand before a change hands off under.
  STATE_CHECK = "state_check".freeze
  UNDO_LIMIT = 500

  class << self
    def kind(value = nil)
      @kind = value if value
      @kind
    end

    def label(value = nil)
      @label = value if value
      @label
    end

    def group(value = nil)
      @group = value if value
      @group
    end

    # Run by the engine itself, so DefinedWorkflow never performs it.
    def engine? = false

    # Whether a step with this config changes something outside Firefight's own run records, decided by what it calls.
    def changes?(_config, _workspace) = false

    # Whether a change made by this step is one a person can put back, so the step must say how before it is published.
    # A message once read cannot be taken back, so those steps carry no undo.
    def undoable?(config, workspace) = changes?(config, workspace)

    # Whether the step reads how something stands outside Firefight, which is what checks a change after it.
    def checks?(_config, _workspace) = false

    # The fields the step hands later steps, which {{steps.<name>.<field>}} may read.
    def output_fields(_config) = []

    # Each problem with the step's config, as a sentence. A step that changes something needs its undo.
    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      return [ "#{named} changes something, so it needs its undo: how a person puts it back." ] if undoable?(config, workspace) && config[KEY_UNDO].to_s.strip.empty?
      return [ "#{named} says how to undo it in at most #{UNDO_LIMIT} characters." ] if config[KEY_UNDO].to_s.length > UNDO_LIMIT

      []
    end

    # What the workflow's own identity needs granted to run the step (DefinedWorkflow::Reach::Needed).
    def reach(_config, _workspace) = []

    # A step that reads the run's data only, as a person reads it on the run's page.
    def describe(config, _workspace) = config.to_h.except(KEY_UNDO).to_json.truncate(200)
  end

  attr_reader :run, :step, :config

  def initialize(run:, step:, config:)
    @run = run
    @step = step
    @config = config.to_h
  end

  def workspace = @run.workspace

  def perform = raise(NotImplementedError, "#{self.class.name} must perform")

  # The step's own row on the run's record, which owns what the step kept, such as Halon's chat.
  def record
    @record ||= Workflow::Run::Step.find_by(run_id: @run.id, step_key: @step.name, iteration: DefinedWorkflow.iteration_of(@step.workflow))
  end

  # Who the step acts as: the workflow's own identity, or the person testing it.
  def principal = @run.acting_principal

  def changes? = self.class.changes?(@config, workspace)

  # A change in a test run that the tester did not turn on, so it is shown rather than made.
  def simulated? = changes? && @run.test? && !@run.real_step_keys.include?(@step.name)

  def simulated_output(would) = { OUTPUT_SIMULATED => true, OUTPUT_WOULD => would }

  # A change inside a freeze window waits for it to end or stops, as the workflow chose. Nothing changes either way.
  def frozen
    window = Workspace::FreezeWindows.covering(workspace, Time.current)
    return unless window

    words = Workspace::FreezeWindows.sentence(window, @run.workflow.time_zone)
    raise Refused, "#{words} Nothing ran." unless @run.workflow.waits_out_freezes?

    SolidWorkflow::Park.new(wake_at: window.ends_at)
  end

  # Before a change in a run nobody pressed, Halon reads how what it changes stands now, as the workflow's own identity,
  # and the step stops unless nothing moved. Asked again after an approval, since time passed while it waited.
  def read_first(named, asked, after: nil)
    return unless @run.reads_first?

    key = [ STATE_CHECK, after ].compact.join(":")
    report = await(key) { WorkflowStateCheckJob.perform_later(@run.id, record&.id, @step.id, key, named, asked) }
    return report if report.is_a?(SolidWorkflow::Park)
    return if report["change"] == Chat::CurrentState::UNCHANGED

    said = Chat::CurrentState::WORDS[report["change"]] || Chat::CurrentState::WORDS[Chat::CurrentState::UNKNOWN]
    raise Refused, [ said, report["state"].presence, "Nothing ran." ].compact.join(" ")
  end

  # Work handed to a job, such as Halon reading, delivered back to the step by name (DefinedWorkflow.deliver!). The first
  # time it is asked for the block hands it off and the step parks. Woken with it delivered, the step has it. Past the
  # step's time limit with nothing delivered, the step fails.
  def await(name)
    delivered = @step.reload.checkpoint.to_h.dig(CHECKPOINT_DELIVERED, name)
    return delivered if delivered

    deadline = handed_off_deadline
    raise SolidWorkflow::TimeLimitReached, "Nothing came back within #{ActiveSupport::Duration.build((deadline - @step.first_started_at).round).inspect}." if deadline <= Time.current

    if DefinedWorkflow.mark_asked!(@step, name)
      ActiveRecord.after_all_transactions_commit { yield }
    end
    SolidWorkflow::Park.new(wake_at: deadline)
  end

  def handed_off_deadline
    started = @step.first_started_at || Time.current
    started + (@step.timeout_seconds || HANDED_OFF_LIMIT.to_i).seconds
  end
end
