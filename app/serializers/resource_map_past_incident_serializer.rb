# An ended incident on a catalog service a resource runs for, with what it came to.
class ResourceMapPastIncidentSerializer < BaseSerializer
  object_as :incident

  type :string
  def id = incident.id

  type :string
  def identifier = incident.identifier

  type :string
  def name = incident.name

  type :string
  def ended_at = incident.ended_at.utc.iso8601

  type :string, optional: true
  def outcome = incident.outcome&.text

  # Where the outcome was read from, such as the postmortem.
  type :string, optional: true
  def outcome_source = incident.outcome&.source
end
