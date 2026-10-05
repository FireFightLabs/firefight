# What the chat's composer takes, so the page says what Halon cannot read before anything is sent.
class AgentChatAttachmentRulesSerializer < BaseSerializer
  object_as :rules

  type :number
  def max_files = rules.max_files

  type :number
  def max_bytes = rules.max_bytes

  type :string
  def max_size = Chat::Attachment.human_size(rules.max_bytes)

  # For the file picker, which offers these first.
  type :string
  def accept = rules.accept

  type :string
  def accepted = Chat::Attachment::ACCEPTED

  type :string
  def too_many = Chat::Attachment::TOO_MANY

  # Said on an image's chip before it is sent when the chat's model is not known to read images.
  type "string | null"
  def images_unread = (Chat::Attachment::IMAGES_UNREAD unless rules.reads_images)
end
