# One time a chat made room, kept so the thresholds can be tuned from what really happened. The dashboard shows each
# one as a quiet line among the steps, never the note, which is the agent talking to itself about what it read.
class Chat::Compaction < ApplicationRecord
  self.table_name = "chat_compactions"

  STAGE_CLEARED = "cleared"
  STAGE_REBUILT = "rebuilt"
  STAGES = [ STAGE_CLEARED, STAGE_REBUILT ].freeze

  # Both stages read the same to a person, since what matters to them is that Halon made room and lost nothing.
  SHOWN_AS = "Shortened its working notes to make room".freeze
  # A step kind of its own, so the page draws it quietly and never counts it as a step Halon took.
  STEP_KIND = "room".freeze

  belongs_to :chat

  # The agent's note to itself quotes what it read.
  encrypts :note

  validates :stage, inclusion: { in: STAGES }

  # Unique among a chat's steps, whose keys are tool call ids.
  def step_key = "compaction-#{id}"
end
