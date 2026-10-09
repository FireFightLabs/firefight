# The deployment's account with one model provider, as far as credit goes. Every workspace shares it, so it is one row
# per provider. It is out of credit from a call refused for good until a call answers again or its balance shows
# credit. The people running Firefight are alerted when it runs out or runs low, at most once per ALERT_INTERVAL.
class AiAccount < ApplicationRecord
  validates :provider, presence: true

  ALERT_INTERVAL = 4.hours

  scope :out_of_credit, -> { where.not(out_of_credit_since: nil) }

  # Alerts go where new installs are announced, the one channel to the people running Firefight there is.
  def self.alerting? = Rails.configuration.x.install_notification_webhook_url.present?

  # True only for the call that moves it from having credit to having none, of however many workers are refused at once.
  def self.ran_out!(provider)
    return false if provider.blank?

    insert({ provider: provider.to_s }, unique_by: :provider)
    where(provider: provider.to_s, out_of_credit_since: nil).update_all(out_of_credit_since: Time.current, updated_at: Time.current) > 0
  end

  # One statement that changes nothing on an account with credit, so every answered call can say it.
  def self.answered!(provider)
    out_of_credit.where(provider: provider.to_s).update_all(out_of_credit_since: nil, updated_at: Time.current) > 0
  end

  def self.refilled!(provider) = answered!(provider)

  # True only for the caller that may alert now, so alerts racing each other, or coming within the interval of the last,
  # send one.
  def self.alert_due!(provider)
    return false if provider.blank?

    insert({ provider: provider.to_s }, unique_by: :provider)
    now = Time.current
    where(provider: provider.to_s).and(where(alerted_at: nil).or(where(alerted_at: ..(now - ALERT_INTERVAL))))
                                  .update_all(alerted_at: now, updated_at: now) > 0
  end
end
