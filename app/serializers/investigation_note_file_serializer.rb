# A file that went with a note to a run, named in the run's story. Only a chat serves the file itself.
class InvestigationNoteFileSerializer < BaseSerializer
  object_as :file

  type :string
  def id = file.id

  type :string
  def name = file.filename

  type :string
  def size = Chat::Attachment.human_size(file.byte_size)

  type :string
  def kind = file.kind

  # Why Halon did not read it, for a file a platform shared that could not be taken.
  type "string | null"
  def unread_reason = file.refusal
end
