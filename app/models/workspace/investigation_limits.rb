module Workspace::InvestigationLimits
  extend ActiveSupport::Concern

  # A guard against a runaway loop, not a limit on how long an investigation may take. Spend and time are that.
  INVESTIGATION_DEFAULT_MAX_TURNS = 500
  # Cents, so there is no floating point money and dollars are only the display.
  INVESTIGATION_DEFAULT_MAX_SPEND_CENTS = 400
  # How long a run may work before it is told to conclude with what it has. Twice a connected coding agent's limit
  # (Integrations::Packs::CodingAgent::TIME_LIMIT), since a run reads several systems and code but never writes a change.
  INVESTIGATION_MAX_DURATION = 60.minutes

  Limits = Data.define(:max_turns, :max_spend_cents, :max_duration)

  included do
    validates :investigation_max_turns,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :investigation_max_spend_cents,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  end

  # A chat question does the work it needs itself, so it may spend what a run may. The turn ends once answered, so a
  # lookup still costs a few calls.
  def conversation_limits = investigation_limits

  def investigation_limits
    Limits.new(
      max_turns: investigation_max_turns || INVESTIGATION_DEFAULT_MAX_TURNS,
      max_spend_cents: investigation_max_spend_cents || INVESTIGATION_DEFAULT_MAX_SPEND_CENTS,
      max_duration: INVESTIGATION_MAX_DURATION
    )
  end
end
