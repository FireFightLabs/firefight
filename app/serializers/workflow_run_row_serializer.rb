# One run as a list shows it: which workflow, what started it, how it went and when.
class WorkflowRunRowSerializer < BaseSerializer
  object_as :run

  type :string
  def id = run.id

  type :string
  def workflow_id = run.workflow_id

  type :string
  def workflow_name = run.workflow.name

  attributes(
    status: { type: :string },
    trigger_kind: { type: :string },
    started_by_kind: { type: :string },
    test: { type: :boolean },
    pinned: { type: :boolean },
    error: { type: :string, optional: true }
  )

  # A timed trigger's own words name a time, which a run it started does not need.
  TRIGGERED_WORDS = { Workflow::Trigger::KIND_SCHEDULE => "Its schedule", Workflow::Trigger::KIND_ONCE_AT => "Its time came" }.freeze

  # Who started it, as a person reads it: their name, or what started it on its own.
  type :string
  def started_by_words
    case run.started_by_kind
    when Workflow::Run::STARTED_BY_PERSON then run.started_by&.display_name || "Someone"
    when Workflow::Run::STARTED_BY_HALON then run.started_by ? "Halon, for #{run.started_by.display_name}" : "Halon"
    when Workflow::Run::STARTED_BY_WORKFLOW then "Another workflow"
    else TRIGGERED_WORDS.fetch(run.trigger_kind) { Workflow::Trigger.words({ Workflow::Trigger::KEY_KIND => run.trigger_kind }) }
    end
  end

  # The same as the start of a sentence, such as "Started by its schedule".
  type :string
  def started_sentence
    case run.started_by_kind
    when Workflow::Run::STARTED_BY_TRIGGER then "Started by #{started_by_words.downcase_first}"
    when Workflow::Run::STARTED_BY_WORKFLOW then "Started by another workflow"
    else "Started by #{started_by_words}"
    end
  end

  type :string
  def created_at = run.created_at.iso8601

  type :string, optional: true
  def finished_at = run.finished_at&.iso8601

  type :boolean
  def details_pruned = run.details_pruned?
end
