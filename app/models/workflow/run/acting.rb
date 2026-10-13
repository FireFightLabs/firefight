# Who a run acts as and what that costs. A run acts as its workflow's own identity, kept on the run as it was when the
# run started. A test run acts as the person testing, so its reads show what they may read and nothing changes unless
# they turn a step on. A run nobody pressed reads how things stand before each change. Its AI spend is every model call
# its steps made, which its workflow's ceiling is held to.
module Workflow::Run::Acting
  extend ActiveSupport::Concern

  # Triggers nobody pressed at the moment the run starts, so a change reads how things stand first.
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

  def ai_spent_cents = (ai_spent_micros / FirefightAi::AgentLoop::MICROS_PER_CENT.to_f).ceil
end
