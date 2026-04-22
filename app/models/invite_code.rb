class InviteCode < ApplicationRecord
  class RedemptionError < StandardError; end

  belongs_to :redeemed_by, class_name: "User", optional: true

  validates :code_digest, presence: true, uniqueness: true

  scope :active, -> { where(redeemed_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.digest_code(raw_code)
    # Codes are case-insensitive; digest the normalized form.
    Digest::SHA256.hexdigest(raw_code.to_s.strip.upcase)
  end

  def self.find_active_by_code(raw_code)
    return nil if raw_code.blank?

    invite_code = find_by(code_digest: digest_code(raw_code))
    invite_code if invite_code&.active?
  end

  def active?
    !redeemed? && !expired?
  end

  def redeemed?
    redeemed_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def redeem!(user)
    now = Time.current
    affected = self.class.active.where(id: id).update_all(
      redeemed_by_id: user.id,
      redeemed_at: now,
      updated_at: now
    )

    raise RedemptionError, "Invite code is no longer available" unless affected == 1

    reload
  end
end
