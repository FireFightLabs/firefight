# One piece of evidence behind a prevented problem: a past incident, a postmortem, a resource on the map, a metric or
# code, and where to open it.
class HalonPreventedEvidenceSerializer < BaseSerializer
  object_as :evidence

  type "ReviewEvidenceKind"
  def kind = evidence.kind

  type :string
  def title = evidence.title

  type :string, optional: true
  def url = evidence.url.presence
end
