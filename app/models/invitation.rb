class Invitation < ApplicationRecord
  DEFAULT_TTL = 7.days

  belongs_to :workspace
  belongs_to :invited_by, class_name: "WorkspaceMembership"
  belongs_to :redeemed_by, class_name: "WorkspaceMembership", optional: true

  validates :email, presence: true, format: URI::MailTo::EMAIL_REGEXP
  validates :expires_at, presence: true
  validates :email, uniqueness: { scope: :workspace_id, conditions: -> { where(redeemed_at: nil) } }

  scope :active,   -> { where(redeemed_at: nil).where("expires_at > ?", Time.current) }
  scope :pending,  -> { where(redeemed_at: nil) }
  scope :redeemed, -> { where.not(redeemed_at: nil) }

  before_validation :set_default_expiry, on: :create

  # Creates the WorkspaceMembership for the redeemer and marks the invite consumed.
  # Returns the new membership.
  def consume!(user:, auth_hash:)
    transaction do
      membership = workspace.auto_provision_member!(user: user, auth_hash: auth_hash)
      update!(redeemed_at: Time.current, redeemed_by: membership)
      membership
    end
  end

  private

  def set_default_expiry
    self.expires_at ||= DEFAULT_TTL.from_now
  end
end
