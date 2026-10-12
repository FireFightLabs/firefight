# What members can read and change in each connection, as Who can do what and the Permissions screen show it. A row is
# set through its read or changes pack's slug, by the same Ability::Role#let_members! the dashboard calls.
class Api::V1::MemberAccessController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_READ)
    @overview = Ability::Role.member_access_of(current_workspace)
  end

  # choice is everyone, nobody or chosen, and people names the chosen members by id or email.
  def update
    authorize!(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE)
    pack = current_workspace.ability_roles.find_by!(slug: params[:id])
    people = Array(params[:people]).map { |reference| current_workspace.workspace_memberships.resolve!(reference.to_s) }
    pack.let_members!(params.require(:choice).to_s, people: people, by: Current.principal)
    @overview = Ability::Role.member_access_of(current_workspace)
    @connection = @overview.connections.find { |connection| connection.integration.id == pack.integration_id }
    render :show
  end
end
