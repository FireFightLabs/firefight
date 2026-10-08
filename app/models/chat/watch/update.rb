# One line a watch said: a milestone, progress inside a run, taking longer than usual, or how it ended. Kept so the chat shows it where it
# happened and Halon hears it at its next turn, never as a message in the model's own chat, which a turn may be writing.
class Chat::Watch::Update < ApplicationRecord
  KIND_STARTED = "started"
  KIND_MILESTONE = "milestone"
  # A job or step inside a run failed while the run went on.
  KIND_PART_FAILED = "part_failed"
  # What it followed never showed up, so Halon is finding another way to follow it.
  KIND_HANDED_BACK = "handed_back"
  KIND_SLOW = "slow"
  # The jobs or steps that started or passed since the last check, one line for everything the watch follows.
  KIND_PROGRESS = "progress"
  KIND_ENDED = "ended"
  KINDS = [ KIND_STARTED, KIND_MILESTONE, KIND_PART_FAILED, KIND_HANDED_BACK, KIND_SLOW, KIND_PROGRESS, KIND_ENDED ].freeze

  belongs_to :watch, class_name: "Chat::Watch", inverse_of: :updates

  validates :kind, inclusion: { in: KINDS }

  scope :untold, -> { where(told_at: nil) }
end
