# One line of a memory's history on the Memory page: what happened, who did it, why, and when.
class ChatMemoryEventSerializer < BaseSerializer
  object_as :event

  type :string
  def id = event.id

  type "ChatMemoryEventKind"
  def kind = event.kind

  # A person, Halon or a postmortem, or nil when nobody is known.
  type "ChatMemoryActor", optional: true
  def actor = event.actor

  # Who did it, in words, such as "Ana" or "Halon".
  type :string, optional: true
  def by = event.by

  # Why, such as what Halon read in production.
  type :string, optional: true
  def detail = event.detail

  type :string
  def at = event.created_at.utc.iso8601
end
