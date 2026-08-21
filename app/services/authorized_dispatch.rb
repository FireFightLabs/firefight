# Slack's single gate into the Ability Gateway, the role Mcp::ToolDispatcher
# plays for tools and the API controllers play for REST. Handlers declare what
# they authorize as; this resolves the acting principal and runs the call
# through the gateway.
module AuthorizedDispatch
  # Raised when the platform never gave us an identity to authorize as. The
  # dispatchers refuse the call rather than running it unattributed.
  class PrincipalUnresolved < StandardError; end

  UNRESOLVED_MESSAGE = "Firefight couldn't verify your workspace account. Please try again in a moment."

  def self.call(handler, subject, context: {})
    authorization = handler.authorization
    return yield if authorization == HandlerAuthorization::NONE

    principal = subject.principal
    raise PrincipalUnresolved unless principal

    resource, crud_action = authorization
    AbilityGateway.authorize!(
      principal: principal,
      action_key: Ability::Action.system_key(resource, crud_action),
      workspace: subject.workspace,
      params: subject.authorization_params,
      context: { source: AbilityGateway::SOURCE_SLACK, approval_id: subject.approval_id }.merge(context)
    ) { yield }
  end

  def self.denied_message(error)
    resource = error.action_key.split(".").first
    "You don't have permission to do that in Firefight (#{error.action_key}). " \
      "Ask a workspace admin to grant you #{resource} access in Settings, Permissions."
  end

  def self.pending_message(approval)
    "That needs a workspace #{approval.required_role} to approve. I've posted the request " \
      "and I'll pick it up again as soon as someone approves. If it's urgent, reach out to an admin directly."
  end
end
