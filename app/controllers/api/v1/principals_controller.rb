class Api::V1::PrincipalsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @principals = Ability::Principal.all(current_workspace)
  end
end
