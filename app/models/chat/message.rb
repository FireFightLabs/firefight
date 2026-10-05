class Chat::Message < ApplicationRecord
  acts_as_message chat: :chat, chat_class: "Chat"

  # Tool results and the model's reasoning are customer data, and the raw columns repeat the thinking.
  encrypts :content, :thinking_text, :thinking_signature,
           :citations, :server_tool_calls, :raw_content, :raw_reasoning

  ROLE_SYSTEM = "system"
  ROLE_USER = "user"
  ROLE_ASSISTANT = "assistant"
  ROLE_TOOL = "tool"
  READABLE_ROLES = [ ROLE_USER, ROLE_ASSISTANT ].freeze

  # Not named attachments, which the library would read and send as they are, unredacted and unframed.
  has_many :attached_files, -> { in_order }, class_name: "Chat::Attachment", foreign_key: :chat_message_id,
                                            dependent: :destroy, inverse_of: :message

  # A person's message is handed over with the files they sent, read the way Chat::Attachment::Reading says.
  def to_llm
    message = super
    files = role == ROLE_USER ? chat.files_sent_with(self) : []
    return message if files.empty?

    shown = 0
    parts = files.map { |file| file.for_model(chat, number: (shown += 1 if chat.shown_whole?(file))) }
    RubyLLM::Message.new(
      role: message.role, content: [ message.content.presence, Chat::Attachment.heading(files.size), *parts.map(&:text) ].compact.join("\n\n"),
      attachments: parts.filter_map(&:whole), cache_until_here: message.cache_until_here?
    )
  end

  def interrupted_reply?
    role == ROLE_ASSISTANT && content.blank? && thinking_text.blank? && raw_content.blank? &&
      !ruby_llm_tool_calls.exists?
  end
end
