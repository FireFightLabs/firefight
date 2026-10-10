# The models a dashboard chat can switch to, and the one it runs on.
class ChatModelMenuSerializer < BaseSerializer
  object_as :menu

  # The model the open chat runs on, or a new chat starts on.
  type :string
  def selected = options.fetch(:selected)

  has_many :models, serializer: ChatModelOptionSerializer
end
