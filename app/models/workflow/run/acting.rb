# Who a run acts as and what that costs. A run acts as its workflow's own identity, kept on the run as it was when the
# run started. A test run acts as the person testing, so its reads show what they may read and nothing changes unless
# they turn a step on. A run nobody pressed checks a change is still needed before making it. What it spends is every
# model call its steps made and the time its sandbox ran, priced as code fixes price theirs (CodeBox#cost_micros), and
# its workflow's spending ceiling holds both.
module Workflow::Run::Acting
  extend ActiveSupport::Concern

  # Triggers nobody pressed at the moment the run starts, so a change checks first that it is still needed.
  UNATTENDED = [ Workflow::Trigger::KIND_SCHEDULE, Workflow::Trigger::KIND_ONCE_AT, *Workflow::Trigger::EVENTS ].freeze

  def acting_principal = test? ? started_by : agent

  def reads_first? = !test? && UNATTENDED.include?(trigger_kind)

  # How the activity log names the run beside each call it made.
  def ledger_label = "#{workflow.name} workflow, run of #{created_at.utc.strftime('%Y-%m-%d %H:%M')} UTC"

  def code_box_key = "workflow-run-#{id}"

  # Every model call the run's steps made, its Halon steps and the reads before its changes alike.
  def ai_spent_micros
    Inference.where(inferable: self).or(Inference.where(inferable_type: Workflow::Run::Step.name, inferable_id: steps.select(:id))).sum(:cost_micros)
  end

  def ai_spent_cents = cents(ai_spent_micros)

  # The run's sandbox, every box started under its key, for the time each ran at its provider's price. A box with no
  # price, such as one on the deployment's own machines, costs nothing here.
  def sandbox_spent_micros = CodeBox.where(workspace_id: workspace_id, key: code_box_key).sum(&:cost_micros)

  def spent_cents = cents(ai_spent_micros + sandbox_spent_micros)

  # What is left of the workflow's spending ceiling, no more than limit, or limit when it sets none.
  def room_cents(limit)
    cap = workflow.cost_cap_cents
    cap ? [ cap - spent_cents, limit ].min : limit
  end

  # Why a step that spends cannot start, once the run spent its ceiling, or nil.
  def spending_blocked_reason
    cap = workflow.cost_cap_cents
    "This run reached its spending ceiling of #{ActiveSupport::NumberHelper.number_to_currency(cap / 100.0)}, so this step did not run." if cap && spent_cents >= cap
  end

  private

  def cents(micros) = (micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).ceil
end
