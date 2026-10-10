# A check Halon runs on a schedule, as the Monitoring page lists it and its dialog edits it.
class InvestigationCheckSerializer < BaseSerializer
  object_as :check

  type :string
  def id = check.id

  attributes(
    name: { type: :string },
    kind: { type: :string },
    notes: { type: :string, optional: true },
    cadence: { type: :string },
    hour: { type: :number },
    weekday: { type: :number, optional: true },
    time_zone: { type: :string }
  )

  type :string
  def kind_label = check.kind_details.label

  type :string
  def schedule = check.schedule_words

  type :boolean
  def enabled = check.enabled?

  type :string, optional: true
  def next_run_at = (check.next_run_at.iso8601 if check.enabled?)

  type :number
  def runs = check.usage_count

  # How its latest run stands and where to read it, nil before it first ran.
  type "{ id: string; status: string; at: string; summary?: string } | null"
  def last_run
    run = check.last_run
    return nil unless run

    { id: run.id, status: run.status, at: (run.completed_at || run.created_at).iso8601, summary: run.finding&.summary || run.stopped_because }.compact
  end

  type :string, optional: true
  def deletion_blocked_reason = check.deletion_blocked_reason

  type :string, optional: true
  def run_blocked_reason = check.run_now_blocked_reason
end
