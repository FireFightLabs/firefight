# Suspension is an operator action, set from the console: abuse review,
# offboarding, or (in the cloud build) a subscription that stayed unpaid after
# dunning ran out. Every entry point checks it and refuses with the message
# below, so a suspended workspace is shut out of Slack, the dashboard, the API,
# MCP, and alert ingest at the door rather than deep inside a flow.
module Workspace::Suspension
  extend ActiveSupport::Concern

  SUSPENSION_PAYMENT_FAILED = "payment_failed"
  SUSPENSION_MISUSE = "misuse"
  SUSPENSION_REASONS = [ SUSPENSION_PAYMENT_FAILED, SUSPENSION_MISUSE ].freeze

  SUSPENSION_MESSAGES = {
    SUSPENSION_PAYMENT_FAILED => "This workspace is suspended because of an unresolved payment issue. Contact support@firefight.app to restore access.",
    SUSPENSION_MISUSE => "This workspace is suspended while we review possible misuse. Contact support@firefight.app."
  }.freeze

  included do
    validates :suspended_reason, inclusion: { in: SUSPENSION_REASONS }, allow_nil: true
    validates :suspended_reason, presence: true, if: :suspended_at?
  end

  def suspended?
    suspended_at.present?
  end

  def suspension_message
    SUSPENSION_MESSAGES.fetch(suspended_reason, "This workspace is suspended. Contact support@firefight.app.")
  end
end
