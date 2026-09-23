# Transcript access is here rather than on Permissions on purpose. A grant says who
# may ask, this says whether the conversation is readable at all.
class WorkspaceSettingsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  def show
    render inertia: "settings/workspace", props: {
      settings: WorkspaceSettingsSerializer.one(current_workspace)
    }
  end

  # A blank retention casts to null, which means keep everything.
  def update
    current_workspace.update_settings!(params.permit(*Workspace::Settings::KEYS))

    redirect_to settings_workspace_path, notice: "Workspace settings were updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end
end
