# Every Inertia page is an authenticated app surface unless it says
# otherwise. The public ones (sign-in, onboarding, error pages) opt out
# explicitly, so a new controller cannot forget the guard.
class InertiaController < ApplicationController
  before_action :block_suspended_workspace
  before_action :require_authentication

  inertia_share do
    {
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace),
      availableWorkspaces: current_user ? CurrentWorkspaceSerializer.many(current_user.workspaces.order(:name)) : [],
      currentUserIsAdmin: current_membership&.admin_access? || false
    }
  end

  private

  def block_suspended_workspace
    return unless user_signed_in? && current_workspace&.suspended?

    render inertia: "errors/suspended",
      props: { message: current_workspace.suspension_message },
      status: :forbidden
  end
end
