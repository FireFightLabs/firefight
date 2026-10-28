# A sign-in to an AI subscription a person started through the subscription proxy and has not finished. The proxy
# holds the sign-in itself, and this row only says whose it is, so the proxy's answer is given to the right workspace.
class SubscriptionSignIn < ApplicationRecord
  STATUS_WAITING = "waiting".freeze
  STATUS_DONE = "done".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_WAITING, STATUS_DONE, STATUS_FAILED ].freeze

  # How long the proxy waits for the address a browser sign-in lands on.
  PASTE_WAIT = 5.minutes

  belongs_to :workspace
  belongs_to :started_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :workspace_ai_account, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :waiting, -> { where(status: STATUS_WAITING) }

  def subscription_definition = AiSubscriptions.find(subscription)

  def site = subscription_definition&.site(proxy)

  def expired? = expires_at.present? && expires_at < Time.current

  def reconnecting? = workspace_ai_account_id.present?

  # One statement, so of two requests asking at once only one finishes it.
  def settle!(status, error: nil)
    self.class.where(id: id, status: STATUS_WAITING).update_all(status: status, error: error, updated_at: Time.current) == 1
  end
end
