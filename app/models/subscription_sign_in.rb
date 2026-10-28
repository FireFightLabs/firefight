# A sign-in to an AI subscription a person started through the subscription proxy. The proxy holds the sign-in itself,
# and this row only says whose it is, so the proxy's answer is given to the right workspace. A row that ended without a
# credential being claimed (cancelled, failed, timed out) is kept until the daily sweep, since the proxy may still have
# made a credential from it, and a credential nobody can tell apart from it is never claimed by anyone.
class SubscriptionSignIn < ApplicationRecord
  STATUS_WAITING = "waiting".freeze
  STATUS_DONE = "done".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_CANCELLED = "cancelled".freeze
  STATUSES = [ STATUS_WAITING, STATUS_DONE, STATUS_FAILED, STATUS_CANCELLED ].freeze

  # How long the proxy waits for the address a browser sign-in lands on.
  PASTE_WAIT = 5.minutes
  # The proxy's clock and Firefight's may differ a little.
  CLOCK_SKEW = 1.minute

  belongs_to :workspace
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :workspace_ai_account, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :waiting, -> { where(status: STATUS_WAITING) }

  def subscription_definition = AiSubscriptions.find(subscription)

  def site = subscription_definition&.site(proxy)

  def waiting? = status == STATUS_WAITING

  def expired? = expires_at.present? && expires_at < Time.current

  def reconnecting? = workspace_ai_account_id.present?

  # Whether the proxy could have made a credential from this sign-in at that time: after it started, and before it
  # ended, which for one still waiting is when the proxy stops waiting on it. One that was claimed holds its own.
  def could_have_made?(at)
    return false if status == STATUS_DONE
    return false if at < created_at - CLOCK_SKEW

    ended = waiting? ? expires_at : updated_at
    ended.nil? || at <= ended + CLOCK_SKEW
  end

  # One statement, so of two requests asking at once only one finishes it.
  def settle!(status, error: nil)
    self.class.where(id: id, status: STATUS_WAITING).update_all(status: status, error: error, updated_at: Time.current) == 1
  end
end
