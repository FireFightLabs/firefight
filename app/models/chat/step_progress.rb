# A coding agent's work on a chat step, kept by tool call so a reload sees what arrived live. Its lines can quote the
# model, so they are encrypted like the chat's messages.
class Chat::StepProgress < ApplicationRecord
  belongs_to :chat

  encrypts :progress

  validates :tool_call_id, :progress, presence: true

  def self.keep!(chat, tool_call_id, work)
    kept = find_or_initialize_by(chat: chat, tool_call_id: tool_call_id)
    kept.update!(progress: work.to_json)
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def work = Chat::CodeFixProgress.from_json(progress)
end
