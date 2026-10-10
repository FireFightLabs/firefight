# One time Halon's loop carried on with a backup model because the one it ran on stopped answering. The chat, a run's
# story and the thread each show it once, as a quiet line among the steps, so nobody wonders why the answer reads
# differently. Kept so how often a provider fails Halon can be read later.
class Chat::ModelSwitch < ApplicationRecord
  self.table_name = "chat_model_switches"

  belongs_to :chat

  validates :failed_model, :backup_model, presence: true

  scope :in_order, -> { order(:created_at, :id) }

  # reason is the error's own name, for whoever reads how a provider failed, never shown to people.
  def self.record!(chat, failed:, backup:, error:)
    chat.model_switches.create!(
      failed_model: failed.model, failed_provider: failed.provider_name, backup_model: backup.model, backup_provider: backup.provider_name,
      reason: error.class.name.demodulize
    )
  end

  # Unique among a chat's steps, whose keys are tool call ids.
  def step_key = "model-switch-#{id}"

  def shown_as = "Carried on with #{backup_model}, since #{failed_model} stopped answering"
end
