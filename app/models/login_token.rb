# A one-time sign-in link. Only the digest is stored, so a database read never yields a working link.
class LoginToken < ApplicationRecord
  SIGN_IN = "sign_in"
  PURPOSES = [ SIGN_IN ].freeze
  LIFETIME = 15.minutes

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true
  validates :purpose, inclusion: { in: PURPOSES }

  scope :unconsumed, -> { where(consumed_at: nil) }
  scope :usable, -> { unconsumed.where("expires_at > ?", Time.current) }

  # Returns the raw token, the only copy there will ever be.
  def self.issue!(email:, purpose: SIGN_IN, requested_ip: nil, user_agent: nil)
    token = SecureRandom.urlsafe_base64(32)
    create!(
      email: email,
      purpose: purpose,
      token_digest: digest(token),
      expires_at: LIFETIME.from_now,
      requested_ip: requested_ip,
      user_agent: user_agent.to_s.first(500)
    )
    token
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_usable(token, purpose: SIGN_IN)
    return nil if token.blank?

    usable.find_by(token_digest: digest(token), purpose: purpose)
  end

  # Two clicks on the same link race here, and the row count says which one won. The winner also closes every other
  # link still open for the address, so an older email in the inbox stops working.
  def self.consume(token, purpose: SIGN_IN)
    return nil if token.blank?

    now = Time.current
    won = usable.where(token_digest: digest(token), purpose: purpose).update_all(consumed_at: now, updated_at: now)
    return nil unless won == 1

    login_token = find_by!(token_digest: digest(token))
    unconsumed.where(email: login_token.email, purpose: purpose).update_all(consumed_at: now, updated_at: now)
    login_token
  end
end
