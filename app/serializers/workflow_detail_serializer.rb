# One workflow as its canvas heads it: what starts it, what its own identity needs and holds, why it cannot be published
# yet, and its settings. The version read is the draft when one is open, so a person sees what publishing would make live.
# The steps themselves are the canvas's document.
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

  # What the workflow's own identity needs for the version shown, and whether it holds each now.
  type "{ key: string; label: string; held: boolean }[]"
  def reach = workflow.standing(shown_version).map { |standing| { key: standing.needed.key, label: standing.needed.label, held: standing.held } }

  type :string, optional: true
  def publish_blocked_reason = shown_version&.draft? ? shown_version.publish_blocked_reason : "There is no draft to publish."

  type :string, optional: true
  def freeze_warning = workflow.freeze_warning

  # The address its inbound webhook trigger starts it at. The secret it is signed with is fetched on its own.
  type :string
  def hook_url = workflow.hook_url

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

  private

  def shown_version = memo.fetch(:shown_version) { workflow.draft || workflow.live_version }
end
