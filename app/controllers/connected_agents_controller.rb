# OAuth connections (MCP clients authorized via the consent screen) listed on
# the API-keys page. Revoking kills the application's tokens and grants for
# this member only.
class ConnectedAgentsController < InertiaController
  def destroy
    application = Doorkeeper::Application.find(params[:id])
    Doorkeeper::AccessToken.revoke_all_for(application.id, current_membership)
    Doorkeeper::AccessGrant.revoke_all_for(application.id, current_membership)

    redirect_to developer_api_keys_path
  end
end
