class Chat::Message < ApplicationRecord
  acts_as_message chat: :chat, chat_class: "Chat"

  # Tool results and the model's reasoning about them are the customer's data. The raw
  # columns carry a second copy of the thinking.
  encrypts :content, :thinking_text, :thinking_signature,
           :citations, :server_tool_calls, :raw_content, :raw_reasoning

  ROLE_ASSISTANT = "assistant"

  def interrupted_reply?
    role == ROLE_ASSISTANT && content.blank? && thinking_text.blank? && raw_content.blank? &&
      !ruby_llm_tool_calls.exists?
  end
end
