# One record on an incident's process timeline.
class OperatorProcessEntrySerializer < BaseSerializer
  object_as :entry

  KIND_UNION = Operator::IncidentProcess::KINDS.map(&:inspect).join(" | ")
  TONE_UNION = Operator::IncidentProcess::TONES.map(&:inspect).join(" | ")

  type :string
  def key = entry.key

  type :string
  def at = entry.at.utc.iso8601

  type KIND_UNION
  def kind = entry.kind

  type TONE_UNION
  def tone = entry.tone

  type :string
  def title = entry.title

  type :string, optional: true
  def detail = entry.detail

  type :string, optional: true
  def technical = entry.technical

  type :string, optional: true
  def retry_step_id = entry.retry_step_id

  type :string, optional: true
  def redeliver_id = entry.redeliver_id

  type :string, optional: true
  def run_id = entry.run_id
end
