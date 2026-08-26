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

  def update
    current_workspace.update!(settings_params)

    redirect_to settings_workspace_path, notice: "Workspace settings were updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end

  private

  # A blank retention means keep everything, which is a choice rather than an
  # omission, so it is stored as null rather than rejected.
  def settings_params
    attributes = params.permit(:transcript_access_enabled).to_h
    attributes[:transcript_retention_days] = params[:transcript_retention_days].presence if params.key?(:transcript_retention_days)
    attributes
  end
end
