class AbilityRolesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!

  def create
    current_workspace.ability_roles.create!(name: params.require(:name))
    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # `action_ids` is the set's full contents, not a delta, so an absent or
  # empty list empties it. Guarding on the key being present would make
  # unticking the last ability depend on how an empty array survives
  # serialization, which is not something this should rest on.
  def update
    current_workspace.ability_roles.find(params[:id]).sync_actions!(permitted_action_ids)

    redirect_to settings_permissions_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_permissions_path, alert: e.record.errors.full_messages.to_sentence
  end

  # Revoking the set revokes it everywhere it was granted, which is the point
  # of granting a set rather than its actions one by one.
  def destroy
    current_workspace.ability_roles.find(params[:id]).destroy!
    redirect_to settings_permissions_path
  end

  private

  def permitted_action_ids
    Ability::Action.where(workspace_id: [ nil, current_workspace.id ])
                   .where(id: Array(params[:action_ids]))
                   .pluck(:id)
  end
end
