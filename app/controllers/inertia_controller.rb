class InertiaController < ApplicationController
  inertia_share do
    {
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace),
      availableWorkspaces: current_user ? CurrentWorkspaceSerializer.many(current_user.workspaces.order(:name)) : []
    }
  end
end
