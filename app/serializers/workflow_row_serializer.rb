# A workflow as the Workflows page lists it: what starts it, how it stands, when it runs next and how it last went.
class WorkflowRowSerializer < BaseSerializer
  object_as :workflow

  type :string
  def id = workflow.id

  attributes(
    name: { type: :string },
    slug: { type: :string },
    description: { type: :string, optional: true },
    enabled: { type: :boolean }
  )

  type :string
  def state = workflow.state

  type :string
  def trigger_words = workflow.trigger_words

  type :boolean
  def one_off = workflow.one_off?

  type :string, optional: true
  def next_run_at = workflow.next_run_at&.iso8601

  type :string, optional: true
  def owner_team_name = workflow.owner_team&.name

  type :number
  def runs = workflow.run_count

  # How its latest run went and where to read it, nil before it first ran.
  type "{ id: string; status: string; at: string; test: boolean } | null"
  def last_run
    run = workflow.latest_run
    run && { id: run.id, status: run.status, at: (run.finished_at || run.created_at).iso8601, test: run.test? }
  end

  # What its Run form asks, the trigger's inputs with their defaults.
  type "{ key: string; question: string; default?: string }[]"
  def inputs = Workflow::Trigger.inputs(workflow.live_version&.trigger).map { |input| input.slice("key", "question", "default").compact }

  type :string, optional: true
  def run_blocked_reason = workflow.start_blocked_reason

  type :string, optional: true
  def deletion_blocked_reason = workflow.deletion_blocked_reason

  type :string, optional: true
  def trigger_refusal = workflow.trigger_refusal
end
