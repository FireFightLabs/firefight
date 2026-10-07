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

  # Served by the page the run is drawn over, under that page's own rule, so whoever sees the file may open it. The page
  # names its address as `file_path`. A file Halon did not read was never kept, so it has none.
  type "string | null"
  def url
    return nil if file.unread?

    options.fetch(:file_path).call(file)
  end

  # Why Halon did not read it, for a file a platform shared that could not be taken.
  type "string | null"
  def unread_reason = file.refusal
end
