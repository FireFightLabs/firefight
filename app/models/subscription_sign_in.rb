# A sign-in to an AI subscription a person started through the subscription proxy. The proxy holds the sign-in itself
# and stamps the credential it saves with this row's id, so the credential is found by it. A row that ended without an
# account (cancelled, failed, timed out) is kept until the daily sweep, so a credential the proxy saved from it anyway
# is known for what it is and removed.
class SubscriptionSignIn < ApplicationRecord
  STATUS_WAITING = "waiting".freeze
  STATUS_DONE = "done".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_CANCELLED = "cancelled".freeze
  STATUSES = [ STATUS_WAITING, STATUS_DONE, STATUS_FAILED, STATUS_CANCELLED ].freeze

  # How long the proxy waits for the address a browser sign-in lands on.
  PASTE_WAIT = 5.minutes

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

  # One statement, so of two requests asking at once only one finishes it.
  def settle!(status, error: nil)
    self.class.where(id: id, status: STATUS_WAITING).update_all(status: status, error: error, updated_at: Time.current) == 1
  end
end
