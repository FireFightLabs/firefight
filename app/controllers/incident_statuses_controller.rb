class IncidentStatusesController < InertiaController
  before_action :require_authentication
  before_action :set_status, only: [ :update, :disable, :enable, :destroy ]

  def create
    lifecycle_stage = IncidentLifecycleStage.find_by!(key: params.require(:lifecycle_stage_key))

    status = current_workspace.incident_statuses.new(
      incident_lifecycle_stage: lifecycle_stage,
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280"
    )

    status.save_in_position!
    redirect_to settings_statuses_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_statuses_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    if @status.update(name: params[:name], description: params[:description], color: params[:color])
      redirect_to settings_statuses_path
    else
      redirect_back fallback_location: settings_statuses_path, inertia: { errors: @status.errors.to_hash }
    end
  end

  def disable
    @status.update!(deleted_at: Time.current)
    redirect_to settings_statuses_path
  end

  def enable
    @status.update!(deleted_at: nil)
    redirect_to settings_statuses_path
  end

  def destroy
    if @status.incidents.exists?
      return redirect_to settings_statuses_path, alert: "Can't delete a status that's in use by incidents. Disable it instead."
    end

    @status.destroy!
    redirect_to settings_statuses_path
  end

  private

  def set_status
    @status = current_workspace.incident_statuses.find(params[:id])
  end
end
