class IncidentSeveritiesController < InertiaController
  before_action :require_authentication
  before_action :set_severity, only: [ :update, :disable, :enable, :destroy ]

  def create
    max_position = current_workspace.incident_severities.maximum(:position) || 0

    severity = current_workspace.incident_severities.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280",
      rank: params.require(:rank).to_i,
      position: max_position + 1
    )

    if severity.save
      redirect_to settings_path(tab: "severities")
    else
      redirect_back fallback_location: settings_path(tab: "severities"), inertia: { errors: severity.errors.to_hash }
    end
  end

  def update
    if @severity.update(name: params[:name], description: params[:description])
      redirect_to settings_path(tab: "severities")
    else
      redirect_back fallback_location: settings_path(tab: "severities"), inertia: { errors: @severity.errors.to_hash }
    end
  end

  def disable
    @severity.update!(deleted_at: Time.current)
    redirect_to settings_path(tab: "severities")
  end

  def enable
    @severity.update!(deleted_at: nil)
    redirect_to settings_path(tab: "severities")
  end

  def destroy
    return redirect_to settings_path(tab: "severities") if @severity.incidents.exists?

    @severity.destroy!
    redirect_to settings_path(tab: "severities")
  end

  private

  def set_severity
    @severity = current_workspace.incident_severities.find(params[:id])
  end
end
