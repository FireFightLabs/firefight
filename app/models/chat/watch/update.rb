# One line a watch said: a milestone, progress inside a run, taking longer than usual, or how it ended. Kept so the chat shows it where it
# happened and Halon hears it at its next turn, never as a message in the model's own chat, which a turn may be writing.
class Chat::Watch::Update < ApplicationRecord
  KIND_STARTED = "started"
  KIND_MILESTONE = "milestone"
  # A job or step inside a run failed while the run went on.
  KIND_PART_FAILED = "part_failed"
  # What it followed never showed up, so Halon is finding a better read for it.
  KIND_HANDED_BACK = "handed_back"
  # Halon gave a step a better read, and the line says what changed.
  KIND_REPAIRED = "repaired"
  # A reading Halon took in the chat disagreed with what the watch had, and the watch now goes by that reading.
  KIND_CORRECTED = "corrected"
  # It made all the reads its ceiling allows this hour, so it waits for the next one.
  KIND_CEILING = "ceiling"
  KIND_SLOW = "slow"
  # The jobs or steps that started or passed since the last check, one line for everything the watch follows.
  KIND_PROGRESS = "progress"
  KIND_ENDED = "ended"
  KINDS = [
    KIND_STARTED, KIND_MILESTONE, KIND_PART_FAILED, KIND_HANDED_BACK, KIND_REPAIRED, KIND_CORRECTED, KIND_CEILING, KIND_SLOW, KIND_PROGRESS, KIND_ENDED
  ].freeze

  belongs_to :watch, class_name: "Chat::Watch", inverse_of: :updates

  validates :kind, inclusion: { in: KINDS }

  scope :untold, -> { where(told_at: nil) }
end
