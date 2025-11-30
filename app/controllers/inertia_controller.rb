# frozen_string_literal: true

class InertiaController < ApplicationController
  inertia_share do
    {
      flash: flash.to_hash,
      currentUser: current_user&.as_json(only: [ :id, :name, :email, :avatar_url ]),
      currentWorkspace: current_workspace&.as_json(only: [ :id, :name, :platform, :avatar_url ])
    }
  end
end
