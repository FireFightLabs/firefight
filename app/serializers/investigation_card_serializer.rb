# A run as a chat's card draws it, found by the tool call that started it.
class InvestigationCardSerializer < BaseSerializer
  object_as :investigation

  attributes(
    id: { type: :string },
    status: { type: :string },
    tool_call_id: { type: :string, optional: true }
  )

  type :string, optional: true
  def question
    investigation.question
  end

  type :string, optional: true
  def incident_id
    investigation.incident&.id
  end

  type :string, optional: true
  def incident_identifier
    investigation.incident&.identifier
  end

  # The answer, or why there is none, so the chat reads without opening the run.
  type :string, optional: true
  def answer
    investigation.finding&.summary || investigation.stopped_because
  end

  # An incident is offered only while the run has none.
  type :boolean
  def suggests_incident
    investigation.incident.nil? && investigation.finding&.suggests_incident == true
  end

  type :number, optional: true
  def duration_seconds
    investigation.duration_seconds
  end

  # What it looked at, as the chat shows its own lookups. The whole of each step is in the run's story.
  type "{ position: number, label: string, status: string }[]"
  def steps
    investigation.steps.where.not(position: nil).map do |step|
      { position: step.position, label: step.shown_label, status: step.status }
    end
  end

  has_many :charts, serializer: ChatChartSerializer do
    investigation.chat&.charts || []
  end
end
