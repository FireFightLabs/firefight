# A notice Firefight writes into a chat is never sent to the model, which read the saved ones as its own replies and
# copied them. An old one has no finish_reason or tool calls, unlike a model's reply, and must open with a notice's words.
class MarkFirefightsOwnChatNotices < ActiveRecord::Migration[8.1]
  NOTICES = [
    "Something went wrong on my side, so I did not finish that one. Ask me again.",
    "I was interrupted before I finished. Ask me again.",
    "I could not finish that one. Ask me something narrower, or start an investigation.",
    "Stopped.",
    "Halon couldn't reach its AI just now."
  ].freeze
  # AiCredit's sentence for an account that could not pay, "Halon cannot answer right now because ...".
  CANNOT = /\AHalon cannot .+ right now because /

  class Message < ActiveRecord::Base
    self.table_name = "chat_messages"
    encrypts :content
  end

  def up
    add_column :chat_messages, :notice, :boolean, null: false, default: false
    Message.reset_column_information

    calls = "SELECT message_id FROM ruby_llm_tool_calls WHERE message_type = 'Chat::Message'"
    Message.where(role: "assistant", finish_reason: nil, nudge: false).where("id NOT IN (#{calls})").find_each do |message|
      said = message.content.to_s.split("\n\n").first.to_s
      message.update_columns(notice: true) if NOTICES.any? { |notice| said.start_with?(notice) } || said.match?(CANNOT)
    end
  end

  def down
    remove_column :chat_messages, :notice
  end
end
