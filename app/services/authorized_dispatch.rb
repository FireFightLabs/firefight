# Slack's single gate into the Ability Gateway, the role Mcp::ToolDispatcher
# plays for tools and the API controllers play for REST.
module AuthorizedDispatch
  # The dispatchers refuse a call with no identity rather than running it unattributed.
  class PrincipalUnresolved < StandardError; end

  UNRESOLVED_MESSAGE = "Firefight couldn't verify your workspace account. Please try again in a moment."

  def self.call(handler, subject, context: {})
    authorization = handler.authorization
    return yield if authorization == HandlerAuthorization::NONE

    principal = resolve_principal(subject)
    raise PrincipalUnresolved unless principal

    resource, crud_action = authorization
    AbilityGateway.authorize!(
      principal: principal,
      action_key: Ability::Action.system_key(resource, crud_action),
      workspace: subject.workspace,
      scope: handler.authorization_scope(subject),
      params: subject.authorization_params,
      context: { source: AbilityGateway::SOURCE_SLACK, approval_id: subject.approval_id }.merge(context)
    ) { yield }
  end

  # Provisioned on demand so a first-time caller is a principal like anyone else.
  def self.resolve_principal(subject)
    WorkspaceMemberProvisioner.find_or_provision!(
      workspace: subject.workspace, platform_user_id: subject.user_id, adapter: subject.workspace.adapter
    )
  rescue StandardError => e
    Rails.logger.warn({ event: "dispatch.principal_unresolved", user_id: subject.user_id, error: e.message }.to_json)
    nil
  end

  # What a person may not do, in words, never the action's key.
  DENIED_VERBS = {
    Ability::Action::ACTION_READ => "see", Ability::Action::ACTION_CREATE => "create", Ability::Action::ACTION_UPDATE => "change",
    Ability::Action::ACTION_DELETE => "delete"
  }.freeze

  def self.denied_message(error)
    resource, crud_action = error.action_key.to_s.split(".", 2)
    label = Ability::Action.label(resource)
    verb = DENIED_VERBS[crud_action]
    what = verb ? "#{verb} #{label.downcase} in Firefight" : "do that in Firefight"
    "You don't have permission to #{what}. Ask a workspace admin to give you #{label} access under Gateway, Permissions."
  end

  def self.pending_message(approval)
    "That needs a workspace #{approval.required_role} to approve. I've posted the request " \
      "and I'll pick it up again as soon as someone approves. If it's urgent, reach out to an admin directly."
  end
end
