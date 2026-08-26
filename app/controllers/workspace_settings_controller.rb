# The workspace's own settings, which until now had no screen at all. Transcript
# access is here rather than on the Permissions page on purpose. A grant says who
# may ask, and this says whether the conversation is readable at all.
class WorkspaceSettingsController < InertiaController
  authorizes Ability::Action::RESOURCE_WORKSPACE, read: :show, update: :update

  def show
    render inertia: "settings/workspace", props: {
      settings: WorkspaceSettingsSerializer.one(current_workspace)
    }
  end

  # A blank retention casts to null, which is the workspace choosing to keep
  # everything rather than a value it failed to give.
  def update
    current_workspace.update!(params.permit(:transcript_access_enabled, :transcript_retention_days))

    redirect_to settings_workspace_path, notice: "Workspace settings were updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end
end
