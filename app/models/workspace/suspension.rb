# Set manually from the console. Every entry point refuses a suspended
# workspace with the message for its reason.
module Workspace::Suspension
  extend ActiveSupport::Concern

  SUSPENSION_PAYMENT_FAILED = "payment_failed"
  SUSPENSION_MISUSE = "misuse"
  SUSPENSION_REASONS = [ SUSPENSION_PAYMENT_FAILED, SUSPENSION_MISUSE ].freeze

  SUSPENSION_MESSAGES = {
    SUSPENSION_PAYMENT_FAILED => "This workspace is suspended because of an unresolved payment issue. Contact your administrator to restore access.",
    SUSPENSION_MISUSE => "This workspace is suspended while possible misuse is reviewed. Contact your administrator."
  }.freeze

  included do
    validates :suspended_reason, inclusion: { in: SUSPENSION_REASONS }, allow_nil: true
    validates :suspended_reason, presence: true, if: :suspended_at?
  end

  def suspended?
    suspended_at.present?
  end

  def suspension_message
    SUSPENSION_MESSAGES.fetch(suspended_reason, "This workspace is suspended. Contact your administrator.")
  end
end
