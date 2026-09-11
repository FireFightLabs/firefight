module Workspace::InvestigationLimits
  extend ActiveSupport::Concern

  INVESTIGATION_DEFAULT_MAX_TURNS = 24
  INVESTIGATION_DEFAULT_MAX_TOKENS = 300_000
  # Ambient runs stay quiet below this. A person who asks always gets an answer.
  INVESTIGATION_DEFAULT_CONFIDENCE_THRESHOLD = 0.7

  included do
    validates :investigation_max_turns,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :investigation_max_tokens,
              numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :investigation_confidence_threshold,
              numericality: { greater_than: 0, less_than_or_equal_to: 1 }, allow_nil: true
  end

  def investigation_turn_limit
    investigation_max_turns || INVESTIGATION_DEFAULT_MAX_TURNS
  end

  def investigation_token_limit
    investigation_max_tokens || INVESTIGATION_DEFAULT_MAX_TOKENS
  end

  def investigation_confidence_bar
    investigation_confidence_threshold || INVESTIGATION_DEFAULT_CONFIDENCE_THRESHOLD
  end
end
