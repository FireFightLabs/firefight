# The agent's saved chat with the model. A restarted or resumed job continues from it.
class Chat < ApplicationRecord
  acts_as_chat messages: :messages, message_class: "Chat::Message"

  belongs_to :workspace
  belongs_to :owner, polymorphic: true

  # DISTINCT ON keeps one row per chat, so a list of chats preloads its previews in one query.
  has_one :last_readable_message,
    -> {
      where(role: Chat::Message::READABLE_ROLES)
        .select("DISTINCT ON (chat_messages.chat_id) chat_messages.*")
        .order("chat_messages.chat_id, chat_messages.created_at DESC")
    },
    class_name: "Chat::Message", inverse_of: false

  validate :owner_in_same_workspace

  # The saved chat holds the system prompt and every tool result too. A person reads the
  # conversation, so only the two sides of it are shown.
  def readable_messages
    messages.where(role: Chat::Message::READABLE_ROLES).order(:created_at)
  end

  # Records which model will run, without opening a connection to the provider.
  def self.open!(owner:, workspace:, model_choice:)
    chat = new(owner: owner, workspace: workspace)
    chat.provider = model_choice.provider if model_choice.provider.present?
    chat.assume_model_exists = model_choice.provider.present? && !FirefightAi.registered?(model_choice.model)
    chat.model = model_choice.model
    chat.save!
    chat
  end

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
