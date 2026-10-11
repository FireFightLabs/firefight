# Gives Firefight paging back the tools of an on-call connection it lost, from the on-call page. Granting decides who
# may do what, so it is the same permission as the Permissions screen.
class PagingGrantsController < InertiaController
  authorizes Ability::Action::RESOURCE_PERMISSIONS, create: :create

  def create
    integration = Integrations::Paging.connections(current_workspace).find { |each| each.id == params[:integration_id] }
    return redirect_to halon_on_call_path, alert: "That on-call tool is no longer connected." unless integration

    blocked = current_workspace.paging_grant_blocked_reason(integration)
    return redirect_to halon_on_call_path, alert: blocked if blocked

    current_workspace.grant_paging!(integration)
    redirect_to halon_on_call_path, notice: "Firefight paging can page through #{integration.display_name} again."
  end
end
