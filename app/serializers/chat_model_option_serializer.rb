# One model in a chat's picker, with the few words that say what it is good for.
class ChatModelOptionSerializer < BaseSerializer
  object_as :option

  type :string
  def id = option.model

  type :string
  def label = option.label

  type :string
  def note = option.note

  # The workspace's main model, which a chat runs on until someone picks another.
  type :boolean
  def default = option.default

  # Said on an image's chip before it is sent when this model is not known to read images.
  type "string | null"
  def images_unread = (Chat::Attachment::IMAGES_UNREAD unless option.reads_images)
end
