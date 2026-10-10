# A time Halon's loop carried on with a backup model, as the chat and a run's story show it.
class ChatModelSwitchSerializer < BaseSerializer
  object_as :switch

  type :string
  def key = switch.step_key

  type :string
  def title = switch.shown_as

  type :string
  def at = switch.created_at.utc.iso8601(3)
end
