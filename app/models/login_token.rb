# A one-time link sent by email, either to sign in or to join a workspace. Only the digest is stored, so a database
# read never yields a working link.
class LoginToken < ApplicationRecord
  SIGN_IN = "sign_in"
  INVITE = "workspace_invite"
  PURPOSES = [ SIGN_IN, INVITE ].freeze
  LIFETIME = 15.minutes
  # An invitation waits for someone to get to their inbox, so it lasts a week.
  LIFETIMES = { SIGN_IN => LIFETIME, INVITE => 7.days }.freeze

  belongs_to :workspace_invitation, optional: true

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :workspace_invitation, presence: true, if: -> { purpose == INVITE }

  scope :unconsumed, -> { where(consumed_at: nil) }
  scope :usable, -> { unconsumed.where("expires_at > ?", Time.current) }

  def self.lifetime(purpose) = LIFETIMES.fetch(purpose)

  # Returns the raw token, the only copy there will ever be.
  def self.issue!(email:, purpose: SIGN_IN, workspace_invitation: nil, requested_ip: nil, user_agent: nil)
    token = SecureRandom.urlsafe_base64(32)
    create!(
      email: email,
      purpose: purpose,
      workspace_invitation: workspace_invitation,
      token_digest: digest(token),
      expires_at: lifetime(purpose).from_now,
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
  # link still open for the address, so an older email in the inbox stops working. An invitation's links are closed
  # only for that invitation, so joining one workspace leaves another's invitation open.
  def self.consume(token, purpose: SIGN_IN)
    return nil if token.blank?

    now = Time.current
    won = usable.where(token_digest: digest(token), purpose: purpose).update_all(consumed_at: now, updated_at: now)
    return nil unless won == 1

    login_token = find_by!(token_digest: digest(token))
    unconsumed.where(email: login_token.email, purpose: purpose, workspace_invitation_id: login_token.workspace_invitation_id)
      .update_all(consumed_at: now, updated_at: now)
    login_token
  end

  # Closes every open link for an invitation, when it is sent again or taken back.
  def self.void_for!(workspace_invitation)
    now = Time.current
    unconsumed.where(workspace_invitation: workspace_invitation).update_all(consumed_at: now, updated_at: now)
  end
end
