# frozen_string_literal: true

class InertiaController < ApplicationController
  inertia_share do
    {
      flash: flash.to_hash,
      currentUser: current_user && CurrentUserSerializer.one(current_user),
      currentWorkspace: current_workspace && CurrentWorkspaceSerializer.one(current_workspace)
    }
  end
end
