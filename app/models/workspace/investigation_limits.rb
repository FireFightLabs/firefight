module Workspace::InvestigationLimits
  extend ActiveSupport::Concern

  INVESTIGATION_DEFAULT_MAX_TURNS = 24
  # Cents, so there is no floating point money and dollars are only the display.
  INVESTIGATION_DEFAULT_MAX_SPEND_CENTS = 400

  Limits = Data.define(:max_turns, :max_spend_cents)

  included do
    validates :investigation_max_turns,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :investigation_max_spend_cents,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  end

  def investigation_limits
    Limits.new(
      max_turns: investigation_max_turns || INVESTIGATION_DEFAULT_MAX_TURNS,
      max_spend_cents: investigation_max_spend_cents || INVESTIGATION_DEFAULT_MAX_SPEND_CENTS
    )
  end
end
