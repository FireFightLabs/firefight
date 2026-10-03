# An answer the team marked wrong, with the lessons Halon took from its incident.
class HalonMistakeSerializer < BaseSerializer
  object_as :mistake

  type :string
  def id = finding.id

  type :string
  def investigation_id = finding.investigation_id

  type :string, optional: true
  def incident_id = incident&.id

  # Named by its incident, or by its question when it has no incident.
  type :string
  def label = incident ? "#{incident.identifier} #{incident.name}" : finding.investigation.question.to_s

  type :string
  def summary = finding.summary

  type :string, optional: true
  def cause = finding.winning_hypothesis&.assertion

  type :string, optional: true
  def marked_at = finding.outcome_at&.utc&.iso8601

  type "{ id: string; text: string; confirmed: boolean }[]"
  def lessons = mistake.lessons.map(&:lesson)

  private

  def finding = mistake.finding

  def incident = finding.investigation.incident
end
