# A coding agent's work on a chat step, kept by tool call so a reload sees what arrived live. Its lines can quote the
# model, so they are encrypted like the chat's messages.
# A call id is unique only within its message, and some models start numbering again in each, so a call is its id and
# when it was made: a row is the call's when it was kept since then (since).
class Chat::StepProgress < ApplicationRecord
  belongs_to :chat

  encrypts :progress

  validates :tool_call_id, :progress, presence: true

  scope :of_call, ->(tool_call_id, since:) { where(tool_call_id: tool_call_id, created_at: since..).order(:created_at) }

  # One worker reports a call's work at a time, so the row is found or made without a race to guard.
  def self.keep!(chat, tool_call_id, work, since:)
    kept = where(chat: chat).of_call(tool_call_id, since: since).last || new(chat: chat, tool_call_id: tool_call_id)
    kept.update!(progress: work.to_json)
    kept
  end

  def work = Chat::CodeFixProgress.from_json(progress)
end
