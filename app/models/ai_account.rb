# The deployment's account with one model provider, as far as credit goes. Every workspace shares it, so it is one row
# per provider. It is out of credit from a call refused for good until a call answers again or its balance shows
# credit, and the people running Firefight are alerted once, when it runs out.
class AiAccount < ApplicationRecord
  validates :provider, presence: true

  scope :out_of_credit, -> { where.not(out_of_credit_since: nil) }

  # Alerts go where new installs are announced, the one channel to the people running Firefight there is.
  def self.alerting? = Rails.configuration.x.install_notification_webhook_url.present?

  # Only the call that moves it from having credit to having none alerts, so two workers refused at once alert once.
  def self.ran_out!(provider)
    return false if provider.blank?

    insert({ provider: provider.to_s }, unique_by: :provider)
    moved = where(provider: provider.to_s, out_of_credit_since: nil).update_all(out_of_credit_since: Time.current, updated_at: Time.current) > 0
    AiAccountAlertJob.perform_later(provider.to_s) if moved
    moved
  end

  # One statement that changes nothing on an account with credit, so every answered call can say it.
  def self.answered!(provider)
    out_of_credit.where(provider: provider.to_s).update_all(out_of_credit_since: nil, updated_at: Time.current) > 0
  end

  def self.refilled!(provider) = answered!(provider)
end
