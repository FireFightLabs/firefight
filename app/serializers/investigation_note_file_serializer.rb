# A file that went with a note to a run, named in the run's story and opened from it.
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

  # Where whoever may read the run opens it. A file Halon did not read was never kept, so it has none.
  type "string | null"
  def url
    return nil if file.unread?

    Rails.application.routes.url_helpers.investigation_file_path(file.chat.owner_id, file)
  end

  # Why Halon did not read it, for a file a platform shared that could not be taken.
  type "string | null"
  def unread_reason = file.refusal
end
