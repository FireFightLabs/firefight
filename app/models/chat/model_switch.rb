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
  # A workspace's subscription refused for its usage limit, until it resets.
  CAUSE_LIMIT_REACHED = "limit_reached".freeze
  CAUSES = [ CAUSE_DOWN, CAUSE_UNAVAILABLE, CAUSE_OUT_OF_CREDIT, CAUSE_KEY_REFUSED, CAUSE_LIMIT_REACHED ].freeze

  belongs_to :chat

  validates :failed_model, :backup_model, presence: true
  validates :cause, inclusion: { in: CAUSES }

  scope :in_order, -> { order(:created_at, :id) }

  # reason is the error's own name, for whoever reads how a provider failed, never shown to people.
  def self.record!(chat, failed:, backup:, error:)
    chat.model_switches.create!(
      failed_model: failed.model, failed_provider: failed.provider_name, backup_model: backup.model, backup_provider: backup.provider_name,
      reason: error.class.name.demodulize, cause: SubscriptionProxy.limit_reached?(failed, error) ? CAUSE_LIMIT_REACHED : cause_of(error)
    )
  end

  # The engine reads why from the class RubyLLM raised (FirefightAi.cause).
  ENGINE_CAUSES = {
    FirefightAi::CAUSE_DOWN => CAUSE_DOWN, FirefightAi::CAUSE_UNAVAILABLE => CAUSE_UNAVAILABLE,
    FirefightAi::CAUSE_OUT_OF_CREDIT => CAUSE_OUT_OF_CREDIT, FirefightAi::CAUSE_KEY_REFUSED => CAUSE_KEY_REFUSED
  }.freeze

  def self.cause_of(error) = ENGINE_CAUSES.fetch(FirefightAi.cause(error))

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
    when CAUSE_LIMIT_REACHED then "This workspace's subscription reached its usage limit for #{failed}"
    else "#{failed} is not answering"
    end
  end

  # A chat switches for the reply it is writing, and a run for what is left of it.
  def for_how_long = chat.owner.is_a?(Investigation) ? "for the rest of this run" : "for this reply"
end
