# The agent's saved conversation with the model, owned by an investigation or a conversation.
# RubyLLM persists every move, so a restarted or resumed job continues from here.
class Chat < ApplicationRecord
  acts_as_chat messages: :messages, message_class: "Chat::Message"

  belongs_to :workspace
  belongs_to :owner, polymorphic: true

  # A worker killed while a tool runs leaves an empty reply row, which RubyLLM
  # would read on resume as the model's final answer and silently end the run.
  def discard_interrupted_reply!
    last_message = messages.reload.last
    return unless last_message&.interrupted_reply?

    last_message.destroy!
    messages.reset
  end
end
