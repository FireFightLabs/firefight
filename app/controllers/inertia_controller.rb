class InertiaController < ApplicationController
  before_action :block_suspended_workspace

  inertia_share do
    {
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace),
      availableWorkspaces: current_user ? CurrentWorkspaceSerializer.many(current_user.workspaces.order(:name)) : []
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
