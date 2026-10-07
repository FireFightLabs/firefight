# Every page is authenticated unless it opts out, so a new controller cannot forget the guard.
class InertiaController < ApplicationController
  include WebAuthorization

  before_action :block_inaccessible_workspace
  before_action :require_authentication
  before_action :authorize_web_action!

  inertia_share do
    {
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace),
      availableWorkspaces: current_user ? CurrentWorkspaceSerializer.many(current_user.workspaces.order(:name)) : [],
      currentUserIsAdmin: current_membership&.admin_access? || false,
      currentUserCan: current_membership ? manageable_resources : {},
      pendingApprovalsCount: current_workspace ? current_workspace.ability_approvals.pending.count : 0,
      # Only an admin can give a pack, so only an admin is shown how many wait.
      waitingPackRequestsCount: current_membership&.admin_access? ? current_workspace.ability_pack_requests.waiting.count : 0,
      agentAvailable: agent_available?
    }
  end

  private

  def agent_available?
    return false unless current_workspace && Investigation.available_for?(current_workspace)

    Conversation.readable_by?(current_membership)
  end

  # One flag per resource, so a page offers exactly the controls the gateway would admit.
  def manageable_resources
    return Ability::Action::RESOURCES.index_with(true) if current_membership.admin_access?

    keys = Ability::Action::RESOURCES.index_with { |resource| Ability::Action.system_key(resource, Ability::Action::ACTION_UPDATE) }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)
    keys.transform_values do |key|
      actions[key].present? && AbilityGateway.permitted?(current_membership, actions[key], key, current_workspace, {})
    end
  end

  # A backend that names a page to lift the block, such as billing, sends the person there. That page's controller
  # skips this guard.
  def block_inaccessible_workspace
    blocked = user_signed_in? && current_workspace&.access_blocked
    return unless blocked
    return redirect_to(blocked.path) if blocked.path.present?

    render inertia: "errors/suspended",
      props: { message: blocked.message },
      status: :forbidden
  end
end
