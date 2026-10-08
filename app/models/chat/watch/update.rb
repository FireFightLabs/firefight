# One line a watch said: a milestone, taking longer than usual, or how it ended. Kept so the chat shows it where it
# happened and Halon hears it at its next turn, never as a message in the model's own chat, which a turn may be writing.
class Chat::Watch::Update < ApplicationRecord
  KIND_STARTED = "started"
  KIND_MILESTONE = "milestone"
  KIND_SLOW = "slow"
  KIND_ENDED = "ended"
  KINDS = [ KIND_STARTED, KIND_MILESTONE, KIND_SLOW, KIND_ENDED ].freeze

  belongs_to :watch, class_name: "Chat::Watch", inverse_of: :updates

  validates :kind, inclusion: { in: KINDS }

  scope :untold, -> { where(told_at: nil) }
end
