# A member's request for a pack, answered from the Permissions screen. Giving is the same grant the screen makes.
class PackRequestsController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: %i[give], update: %i[dismiss]

  def give
    answer { |request| PackRequestService.give!(request, by: current_membership) }
  end

  def dismiss
    answer { |request| PackRequestService.dismiss!(request, by: current_membership) }
  end

  private

  def answer
    result = yield current_workspace.ability_pack_requests.find(params[:id])
    redirect_to gateway_permissions_path, (result.ok ? :notice : :alert) => result.words
  end
end
