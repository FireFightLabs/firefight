class Api::V1::AbilitiesController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @abilities = Ability::Grant.grantable_actions(current_workspace)
  end
end
