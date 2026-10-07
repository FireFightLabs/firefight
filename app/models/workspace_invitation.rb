# A teammate an admin asked to join by email. The link in the email is a LoginToken, and following it signs the person
# in and makes them a member, with or without a chat account.
class WorkspaceInvitation < ApplicationRecord
  # Every invitation sends an email, so one workspace sends at most this many in an hour, resends included.
  SENDS_PER_HOUR = 30
  MAX_EMAIL_LENGTH = 254
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  UNAVAILABLE_REASON = "Inviting by email needs outgoing email, which this Firefight is not set up for.".freeze
  ACCEPTED_REASON = "This invitation was already accepted.".freeze
  REVOKED_REASON = "This invitation was revoked.".freeze

  belongs_to :workspace
  belongs_to :invited_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :membership, class_name: "WorkspaceMembership", optional: true
  has_many :login_tokens, dependent: :delete_all

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, length: { maximum: MAX_EMAIL_LENGTH }, format: { with: EMAIL_FORMAT }
  validates :last_sent_at, presence: true
  validate :not_a_member, on: :create

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil) }

  def self.valid_email?(email)
    email.length <= MAX_EMAIL_LENGTH && EMAIL_FORMAT.match?(email)
  end

  # Nil when this Firefight can send invitations at all.
  def self.unavailable_reason
    UNAVAILABLE_REASON unless SignInMethods.email?
  end

  # count is how many emails the request would send.
  def self.send_blocked_reason(workspace, count = 1)
    sent = LoginToken.joins(:workspace_invitation)
      .where(workspace_invitations: { workspace_id: workspace.id })
      .where("login_tokens.created_at > ?", 1.hour.ago)
      .count
    return nil if sent + count <= SENDS_PER_HOUR

    "This workspace has sent #{sent} #{"invitation".pluralize(sent)} in the last hour, and can send #{SENDS_PER_HOUR} an hour. Try again later."
  end

  def pending? = accepted_at.nil? && revoked_at.nil?

  def expires_at = last_sent_at + LoginToken.lifetime(LoginToken::INVITE)

  def expired? = expires_at <= Time.current

  def resend_blocked_reason
    return ACCEPTED_REASON if accepted_at
    return REVOKED_REASON if revoked_at

    self.class.send_blocked_reason(workspace)
  end

  # The token that goes in the email. Older links for this invitation stop working.
  def issue_link!
    LoginToken.void_for!(self)
    token = LoginToken.issue!(email: email, purpose: LoginToken::INVITE, workspace_invitation: self)
    update!(last_sent_at: Time.current)
    token
  end

  # A guarded update, so a revoke and an acceptance at the same moment cannot both win.
  def revoke!
    now = Time.current
    revoked = self.class.pending.where(id: id).update_all(revoked_at: now, updated_at: now) == 1
    LoginToken.void_for!(self)
    reload
    revoked
  end

  # Claims the invitation, then seats the person. Nil when it was revoked or accepted in the meantime. Someone who is
  # already a member keeps the seat they have.
  def accept!(user)
    transaction do
      now = Time.current
      claimed = self.class.pending.where(id: id).update_all(accepted_at: now, updated_at: now) == 1
      next nil unless claimed

      membership = seat!(user, now)
      update!(membership: membership)
      membership
    end
  end

  private

  def seat!(user, now)
    workspace.workspace_memberships.find_by(user: user) ||
      WorkspaceMembership.transaction(requires_new: true) do
        workspace.workspace_memberships.create!(user: user, role: :member, joined_at: now)
      end
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    workspace.workspace_memberships.find_by(user: user) || raise
  end

  def not_a_member
    return if email.blank? || workspace.nil?

    errors.add(:base, "#{email} is already a member of this workspace.") if workspace.workspace_memberships.joins(:user).exists?(users: { email: email })
  end
end
