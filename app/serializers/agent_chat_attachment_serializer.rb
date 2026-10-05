# A file a person sent Halon, on their message in the chat or on its chip before it is sent.
class AgentChatAttachmentSerializer < BaseSerializer
  object_as :file

  type :string
  def id = file.id

  type :string
  def name = file.filename

  type :string
  def size = Chat::Attachment.human_size(file.byte_size)

  type :string
  def kind = file.kind

  # Where the file is read from, only by whoever may read the chat it went with.
  type :string
  def url = Rails.application.routes.url_helpers.agent_chat_attachment_path(file)

  # Why Halon did not read it, for a file a platform shared that could not be taken.
  type "string | null"
  def unread_reason = file.refusal
end
