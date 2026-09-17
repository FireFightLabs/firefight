# Every tool the agent uses goes through the gateway, so the ledger holds a row before the call and
# its outcome after. params names what was asked and never carries a payload.
class Chat::ToolCall
  def self.run!(workspace:, principal:, action_key:, params: {}, context: {})
    authorization = AbilityGateway.authorize!(
      principal: principal, action_key: action_key, workspace: workspace, params: params, context: context
    )

    begin
      value = yield authorization
      authorization.finalize_success!
      value
    rescue StandardError => error
      authorization.finalize_error!(error)
      raise
    end
  end
end
