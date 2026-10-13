# What a person sent while the agent was working. It joins the chat at the agent's next step, because a message written
# straight into the chat could land between a tool call and its result, which a provider refuses.
class Chat::QueuedMessage < ApplicationRecord
  self.table_name = "chat_queued_messages"

  belongs_to :chat
  belongs_to :sender, class_name: "WorkspaceMembership", optional: true
  has_many :attached_files, -> { in_order }, class_name: "Chat::Attachment", foreign_key: :queued_message_id,
                                            dependent: :nullify, inverse_of: :queued_message

  # The person's own words, like every message. Written in the chat platform, content is how the model reads them and
  # as_written how the platform sent them. context is what Halon reads before them that the person never wrote, such as
  # the message they replied to, kept apart so it never shows as theirs.
  encrypts :content, :as_written, :context

  validates :content, presence: true, unless: -> { attached_files.any? }

  scope :waiting, -> { where(taken_at: nil).order(:created_at, :id) }

  # One guarded update, so a running turn and the job queued behind it never both add the same message.
  def take!
    self.class.where(id: id, taken_at: nil).update_all(taken_at: Time.current) == 1
  end
end
