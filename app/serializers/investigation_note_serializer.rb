# What a responder added to a run while it worked, and when the run read it.
class InvestigationNoteSerializer < BaseSerializer
  object_as :note

  attributes(id: { type: :string })

  type :string
  def content
    note.content
  end

  has_one :author, serializer: ActorCompactSerializer, optional: true do
    note.sender
  end

  type :string
  def created_at
    note.created_at.utc.iso8601
  end

  # Nil while it waits for the run's next step.
  type :string, optional: true
  def taken_at
    note.taken_at&.utc&.iso8601
  end
end
