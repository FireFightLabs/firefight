class Chat::Message < ApplicationRecord
  acts_as_message chat: :chat, chat_class: "Chat"

  # Who wrote a person's message, kept so a chat several people speak in can tell them apart.
  belongs_to :sender, class_name: "WorkspaceMembership", optional: true

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

  # A person's message is handed over with the files they sent, read the way Chat::Attachment::Reading says, and headed
  # with who wrote it where several people speak.
  def to_llm
    message = super
    files = role == ROLE_USER ? chat.files_sent_with(self) : []
    name = named_sender
    return message if files.empty? && name.nil?

    words = name ? "#{name} wrote:\n#{message.content}" : message.content.presence
    shown = 0
    parts = files.map { |file| file.for_model(chat, number: (shown += 1 if chat.shown_whole?(file))) }
    RubyLLM::Message.new(
      role: message.role, content: [ words, (Chat::Attachment.heading(files.size) if files.any?), *parts.map(&:text) ].compact.join("\n\n"),
      attachments: parts.filter_map(&:whole), cache_until_here: message.cache_until_here?
    )
  end

  def interrupted_reply?
    role == ROLE_ASSISTANT && content.blank? && thinking_text.blank? && raw_content.blank? &&
      !ruby_llm_tool_calls.exists?
  end

  private

  def named_sender
    return nil unless role == ROLE_USER && !nudge && sender_id && chat.speakers_named?

    chat.sender_name(self)
  end
end
