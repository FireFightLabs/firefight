class IncidentStatusesController < InertiaController
  before_action :require_authentication
  before_action :set_status, only: [ :update, :disable, :enable, :destroy ]

  def create
    lifecycle_stage = IncidentLifecycleStage.find_by!(key: params.require(:lifecycle_stage_key))
    max_position = current_workspace.incident_statuses.maximum(:position) || 0

    status = current_workspace.incident_statuses.new(
      incident_lifecycle_stage: lifecycle_stage,
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280",
      position: max_position + 1
    )

    if status.save
      redirect_to settings_path(tab: "statuses")
    else
      redirect_back fallback_location: settings_path(tab: "statuses"), inertia: { errors: status.errors.to_hash }
    end
  end

  def update
    if @status.update(name: params[:name], description: params[:description])
      redirect_to settings_path(tab: "statuses")
    else
      redirect_back fallback_location: settings_path(tab: "statuses"), inertia: { errors: @status.errors.to_hash }
    end
  end

  def disable
    @status.update!(deleted_at: Time.current)
    redirect_to settings_path(tab: "statuses")
  end

  def enable
    @status.update!(deleted_at: nil)
    redirect_to settings_path(tab: "statuses")
  end

  def destroy
    return redirect_to settings_path(tab: "statuses") if @status.incidents.exists?

    @status.destroy!
    redirect_to settings_path(tab: "statuses")
  end

  private

  def set_status
    @status = current_workspace.incident_statuses.find(params[:id])
  end
end
