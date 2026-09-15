# The agent's saved chat with the model. A restarted or resumed job continues from it.
class Chat < ApplicationRecord
  acts_as_chat messages: :messages, message_class: "Chat::Message"

  belongs_to :workspace
  belongs_to :owner, polymorphic: true

  validate :owner_in_same_workspace

  # A killed worker leaves an empty reply that RubyLLM reads as the final answer. Only the job holding the run may call this.
  def discard_interrupted_reply!
    last_message = messages.reload.last
    return unless last_message&.interrupted_reply?

    last_message.destroy!
    messages.reset
  end

  private

  def owner_in_same_workspace
    return if owner.nil? || owner.workspace_id == workspace_id

    errors.add(:owner, "must belong to the same workspace")
  end
end
