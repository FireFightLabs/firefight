# One time Halon's loop carried on with another model because the one it ran on could not answer: the provider stopped
# answering, the model is not available on the account, or the account behind a model a person picked ran out of credit
# or had its key refused. The chat, a run's story and the thread each show it once, as a quiet line among the steps, so
# nobody wonders why the answer reads differently. Kept so how often a provider fails Halon can be read later.
class Chat::ModelSwitch < ApplicationRecord
  self.table_name = "chat_model_switches"

  CAUSE_DOWN = "down".freeze
  CAUSE_UNAVAILABLE = "unavailable".freeze
  CAUSE_OUT_OF_CREDIT = "out_of_credit".freeze
  CAUSE_KEY_REFUSED = "key_refused".freeze
  CAUSES = [ CAUSE_DOWN, CAUSE_UNAVAILABLE, CAUSE_OUT_OF_CREDIT, CAUSE_KEY_REFUSED ].freeze

  belongs_to :chat

  validates :failed_model, :backup_model, presence: true
  validates :cause, inclusion: { in: CAUSES }

  scope :in_order, -> { order(:created_at, :id) }

  # reason is the error's own name, for whoever reads how a provider failed, never shown to people.
  def self.record!(chat, failed:, backup:, error:)
    chat.model_switches.create!(
      failed_model: failed.model, failed_provider: failed.provider_name, backup_model: backup.model, backup_provider: backup.provider_name,
      reason: error.class.name.demodulize, cause: cause_of(error)
    )
  end

  def self.cause_of(error)
    return CAUSE_OUT_OF_CREDIT if AiPayer.out_of_credit?(error)
    return CAUSE_KEY_REFUSED if AiPayer.key_refused?(error)
    return CAUSE_UNAVAILABLE if FirefightAi.model_unavailable?(error)

    CAUSE_DOWN
  end

  # Unique among a chat's steps, whose keys are tool call ids.
  def step_key = "model-switch-#{id}"

  def shown_as
    failed = AiProviders.model_label(failed_provider, failed_model)
    backup = AiProviders.model_label(backup_provider, backup_model)
    "#{why(failed)}, so I switched to #{backup} #{for_how_long}."
  end

  private

  def why(failed)
    case cause
    when CAUSE_UNAVAILABLE then "#{failed} is not available on this account"
    when CAUSE_OUT_OF_CREDIT then "The account behind #{failed} is out of credit"
    when CAUSE_KEY_REFUSED then "The key behind #{failed} was refused"
    else "#{failed} is not answering"
    end
  end

  # A chat switches for the reply it is writing, and a run for what is left of it.
  def for_how_long = chat.owner.is_a?(Investigation) ? "for the rest of this run" : "for this reply"
end
