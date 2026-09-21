# One time a chat made room, kept so the thresholds can be tuned from what really happened.
class Chat::Compaction < ApplicationRecord
  self.table_name = "chat_compactions"

  STAGE_CLEARED = "cleared"
  STAGE_REBUILT = "rebuilt"
  STAGES = [ STAGE_CLEARED, STAGE_REBUILT ].freeze

  belongs_to :chat

  # The agent's note to itself quotes what it read.
  encrypts :note

  validates :stage, inclusion: { in: STAGES }
end
