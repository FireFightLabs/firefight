# The dashboard's gate into the Ability Gateway, as AuthorizedDispatch is for Slack and ApiAuthentication for REST.
module WebAuthorization
  extend ActiveSupport::Concern

  # The including controller registers authorize_web_action! after its authentication
  # guard, so an anonymous request goes to sign in, not the gateway.
  included do
    class_attribute :authorized_actions, default: {}.freeze
    around_action :finalize_web_authorization
  end

  class_methods do
    # authorizes Ability::Action::RESOURCE_WEBHOOKS, create: :create, update: %i[update test], delete: :destroy
    def authorizes(resource, mapping)
      table = authorized_actions.dup
      mapping.each do |crud_action, action_names|
        Array(action_names).each { |name| table[name.to_s] = [ resource, crud_action.to_s ] }
      end
      self.authorized_actions = table.freeze
    end
  end

  def self.denied_message(error)
    resource = Ability::Action.resource_of(error.action_key)
    "You don't have permission to change #{Ability::Action.label(resource).downcase}. " \
      "Ask a workspace admin to grant you #{resource} access under Gateway, Permissions."
  end

  def self.pending_message(approval)
    "That needs a workspace #{approval.required_role} to approve. Your request has been sent " \
      "and will run as soon as someone approves it. You'll get a message either way."
  end

  private

  def authorize_web_action!
    resource, crud_action = self.class.authorized_actions[action_name]
    return unless resource

    authorize_web!(resource, crud_action)
  end

  # For cases a static mapping cannot express. Redirects and returns false when refused.
  def authorize_web!(resource, crud_action)
    @web_authorization = AbilityGateway.authorize!(
      principal: current_membership,
      action_key: Ability::Action.system_key(resource, crud_action),
      workspace: current_workspace,
      params: web_authorization_params,
      context: { source: AbilityGateway::SOURCE_WEB, approval_id: replayed_approval_id }
    )
    true
  rescue AbilityGateway::Denied => e
    redirect_back_or_to dashboard_path, alert: WebAuthorization.denied_message(e)
    false
  rescue AbilityGateway::PendingApproval => e
    ApprovalResumption.park_web!(e.approval, request, membership: current_membership)
    redirect_back_or_to dashboard_path, notice: WebAuthorization.pending_message(e.approval)
    false
  end

  # Binds an approval to this exact request, route, record and body. The body stays out of the ledger.
  def web_authorization_params
    {
      "method" => request.request_method,
      "path" => request.path,
      "body_digest" => Digest::SHA256.hexdigest(request.raw_post.to_s)
    }
  end

  def finalize_web_authorization
    yield
    @web_authorization&.finalize_success!
  rescue => error
    @web_authorization&.finalize_error!(error)
    raise
  end

  def replayed_approval_id
    request.env.dig(WebRequestReplay::ENV_KEY, "approval_id")
  end
end
