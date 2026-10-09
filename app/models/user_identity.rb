# One way a person signs in, such as a Google account, a Slack account in one team, or their email address.
class UserIdentity < ApplicationRecord
  GOOGLE = "google"
  SLACK = "slack"
  EMAIL = "email"
  PROVIDERS = [ GOOGLE, SLACK, EMAIL ].freeze
  LABELS = { GOOGLE => "Google", SLACK => "Slack", EMAIL => "Email link" }.freeze
  # The OmniAuth strategy each sign-in runs through, by the provider it signs in with.
  STRATEGIES = { "google_oauth2" => GOOGLE, "slack_openid" => SLACK, "slack" => SLACK }.freeze

  LAST_METHOD_REASON = "This is your only way to sign in, so it cannot be removed."

  belongs_to :user, inverse_of: :identities

  normalizes :email, with: ->(email) { email.strip.downcase.presence }

  validates :provider, inclusion: { in: PROVIDERS }
  validates :uid, presence: true, uniqueness: { scope: :provider }

  def self.label_for_strategy(strategy) = LABELS[STRATEGIES[strategy.to_s]]

  def label = LABELS.fetch(provider)
  def description = email ? "#{label} (#{email})" : label

  # Reads the user's loaded identities when the caller loaded them, so a list asks once.
  def removal_blocked_reason
    LAST_METHOD_REASON unless user.identities.many?
  end

  # Locks the person so two removals at once cannot both see another method left and leave none.
  def remove!
    user.with_lock do
      reason = removal_blocked_reason
      raise ActiveRecord::RecordNotDestroyed.new(reason, self) if reason

      destroy!
    end
  end
end
