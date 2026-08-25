# Every Inertia page is an authenticated app surface unless it says
# otherwise. The public ones (sign-in, onboarding, error pages) opt out
# explicitly, so a new controller cannot forget the guard.
class InertiaController < ApplicationController
  include WebAuthorization

  before_action :block_suspended_workspace
  before_action :require_authentication
  before_action :authorize_web_action!

  inertia_share do
    {
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace),
      availableWorkspaces: current_user ? CurrentWorkspaceSerializer.many(current_user.workspaces.order(:name)) : [],
      currentUserIsAdmin: current_membership&.admin_access? || false,
      currentUserCan: current_membership ? manageable_resources : {},
      pendingApprovalsCount: current_workspace ? current_workspace.ability_approvals.pending.count : 0
    }
  end

  private

  # Which settings the viewer may change, one flag per resource, so a page
  # offers exactly the controls the gateway would admit.
  def manageable_resources
    return Ability::Action::RESOURCES.index_with(true) if current_membership.admin_access?

    keys = Ability::Action::RESOURCES.index_with { |resource| Ability::Action.system_key(resource, Ability::Action::ACTION_UPDATE) }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)
    keys.transform_values do |key|
      actions[key].present? && AbilityGateway.permitted?(current_membership, actions[key], key, {})
    end
  end

  def block_suspended_workspace
    return unless user_signed_in? && current_workspace&.suspended?

    render inertia: "errors/suspended",
      props: { message: current_workspace.suspension_message },
      status: :forbidden
  end
end
