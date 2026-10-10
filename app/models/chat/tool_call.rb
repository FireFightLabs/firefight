# Every tool the agent uses goes through the gateway, so the ledger holds a row before the call and
# its outcome after. params names what was asked and never carries a payload.
class Chat::ToolCall
  # What a call gave back, and the number of the step a run recorded it under. A chat records no step.
  Outcome = Data.define(:value, :step) do
    def initialize(value:, step: nil) = super
  end

  # holdable: false is for a call already refused by one of Firefight's own rules, which is ledgered but never waits for
  # an approval, since nothing would run once it was given.
  def self.run!(workspace:, principal:, action_key:, params: {}, scope: {}, context: {}, holdable: true)
    authorization = AbilityGateway.authorize!(
      principal: principal, action_key: action_key, workspace: workspace, scope: scope, params: params, context: context, holdable: holdable
    )

    begin
      value = yield authorization
      authorization.finalize_answered!
      value
    rescue StandardError => error
      authorization.finalize_error!(error)
      raise
    end
  end

  # Whether an approval rule covers the call, for a way in that only reads and has nobody to approve it, such as a watch.
  # params is the call, since a read through a tool that can also change things is never held.
  def self.held_by_rule?(workspace:, action_key:, scope: {}, params: {})
    action = Ability::Action.lookup(action_key, workspace)
    action.present? && AbilityGateway.approval_requirement(workspace, action, action_key, scope, {}, params: params).present?
  end
end
