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
end
