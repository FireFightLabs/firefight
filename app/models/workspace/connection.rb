# Whether Firefight can still talk to the workspace's chat platform. Set when
# the platform says the install is gone (a revoked token, an inactive
# account, a refresh token that no longer works) and cleared by a reinstall.
# A disconnected workspace stays readable on the dashboard and asks an admin
# to reinstall. Platform-neutral on purpose: Teams lands on the same columns.
module Workspace::Connection
  extend ActiveSupport::Concern

  DISCONNECTED_TOKEN_REVOKED = "token_revoked"
  DISCONNECTED_ACCOUNT_INACTIVE = "account_inactive"
  DISCONNECTED_REFRESH_FAILED = "invalid_refresh_token"
  DISCONNECT_REASONS = [ DISCONNECTED_TOKEN_REVOKED, DISCONNECTED_ACCOUNT_INACTIVE, DISCONNECTED_REFRESH_FAILED ].freeze

  included do
    validates :disconnected_reason, inclusion: { in: DISCONNECT_REASONS }, allow_nil: true
    validates :disconnected_reason, presence: true, if: :disconnected_at?

    scope :connected, -> { where(disconnected_at: nil) }
  end

  def disconnected?
    disconnected_at.present?
  end

  # Only the first report wins, so parallel jobs noticing the same dead
  # install do not keep rewriting the timestamp.
  def mark_disconnected!(reason)
    return false unless DISCONNECT_REASONS.include?(reason)

    moved = self.class.where(id: id, disconnected_at: nil)
      .update_all(disconnected_at: Time.current, disconnected_reason: reason, updated_at: Time.current) > 0
    reload if moved
    moved
  end

  def mark_connected!
    update!(disconnected_at: nil, disconnected_reason: nil) if disconnected?
  end
end
