# One workflow as its own page shows it: what starts it, each step in order with whether it reads or changes and how it
# is undone, what its own identity needs and holds, why it cannot be published yet, its settings and Halon's suggestions.
# The version shown is the draft when one is open, so a person sees what publishing would make live.
class WorkflowDetailSerializer < WorkflowRowSerializer
  type :number, optional: true
  def live_number = workflow.live_version&.number

  type :number, optional: true
  def draft_number = shown_version&.draft? ? shown_version.number : nil

  # The draft's revision as shown, which Publish sends back so a draft changed since is not published unseen.
  type :number, optional: true
  def draft_revision = shown_version&.draft? ? shown_version.revision : nil

  type :boolean
  def shows_draft = shown_version&.draft? || false

  type :string, optional: true
  def shown_trigger_words = shown_version && Workflow::Trigger.words(shown_version.trigger)

  # Each step in the order it runs, inside each for each too.
  type "{ id: string; name: string; kind: string; kindLabel: string; group: string; changes: boolean; summary: string; undo?: string }[]"
  def steps
    return [] unless shown_version

    kinds = shown_version.step_kinds
    Workflow::Version.all_steps(shown_version.steps).map do |step|
      kind = kinds[step["id"]]
      config = step["config"].to_h
      {
        id: step["id"], name: step["name"].to_s, kind: step["kind"].to_s, kindLabel: kind&.label || step["kind"].to_s.humanize,
        group: kind&.group || DefinedWorkflow::Steps::Base::GROUP_CONTROL, changes: kind&.changes?(config, workflow.workspace) || false,
        summary: kind ? kind.describe(config, workflow.workspace).to_s : "", undo: config[DefinedWorkflow::Steps::Base::KEY_UNDO].presence
      }.compact
    end
  end

  # What the workflow's own identity needs for the version shown, and whether it holds each now.
  type "{ key: string; label: string; held: boolean }[]"
  def reach = workflow.standing(shown_version).map { |standing| { key: standing.needed.key, label: standing.needed.label, held: standing.held } }

  type :string, optional: true
  def publish_blocked_reason = shown_version&.draft? ? shown_version.publish_blocked_reason : "There is no draft to publish."

  type :string, optional: true
  def freeze_warning = workflow.freeze_warning

  type :string, optional: true
  def trigger_refused_at = workflow.trigger_refused_at&.iso8601

  type :string
  def freeze_behaviour = workflow.freeze_behaviour

  attributes(
    cost_cap_cents: { type: :number, optional: true },
    runs_per_hour: { type: :number },
    subject_key: { type: :string, optional: true },
    all_clear: { type: :boolean },
    owner_team_id: { type: :string, optional: true },
    library_key: { type: :string, optional: true }
  )

  type :string, optional: true
  def agent_name = workflow.agent&.name

  # The steps a test run may make for real, by their id, since a test pretends every change unless turned on.
  type "{ id: string; name: string }[]"
  def changing_steps = Array(shown_version&.steps_that_change).map { |step| { id: step["id"], name: step["name"].to_s } }

  # The test form asks the same inputs as a run, read from the version a test runs.
  type "{ key: string; question: string; default?: string }[]"
  def test_inputs = Workflow::Trigger.inputs(shown_version&.trigger).map { |input| input.slice("key", "question", "default").compact }

  # Halon's suggested changes waiting for a person, one per change set, each with why and the run that prompted it.
  type "{ id: string; reason: string; runId?: string; changes: string[]; at: string }[]"
  def suggestions
    workflow.proposals.group_by(&:change_set_id).map do |change_set_id, edits|
      first = edits.first
      { id: change_set_id, reason: first.reason.to_s, runId: first.source_run_id, at: first.created_at.iso8601,
        changes: edits.map { |edit| Workflow::Edit::Described.sentence(edit, shown_version || workflow.live_version) } }.compact
    end
  end

  private

  def shown_version = memo.fetch(:shown_version) { workflow.draft || workflow.live_version }
end
