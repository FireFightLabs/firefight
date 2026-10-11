# The plan setup's plan step offers, as a hosted build describes it (Entitlements::Plan). The sentences arrive finished.
class SetupPlanSerializer < BaseSerializer
  object_as :plan

  type :boolean
  def active
    plan.active?
  end

  type :string
  def price
    plan.price
  end

  type :string
  def price_note
    plan.price_note
  end

  type "string[]"
  def included
    plan.included
  end

  # Nil when starting charges at once rather than opening a trial.
  type :number, optional: true
  def trial_days
    plan.trial_days
  end

  type :string
  def terms
    plan.terms
  end

  type :string, optional: true
  def summary
    plan.summary
  end

  type :string
  def start_path
    plan.start_path
  end

  type :string, optional: true
  def start_blocked_reason
    plan.start_blocked_reason
  end
end
