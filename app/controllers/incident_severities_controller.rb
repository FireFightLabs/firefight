class IncidentSeveritiesController < InertiaController
  before_action :require_authentication
  before_action :require_admin!
  before_action :set_severity, only: [ :update, :disable, :enable, :destroy ]

  def create
    severity = current_workspace.incident_severities.new(
      name: params.require(:name),
      slug: params.require(:name).parameterize(separator: "_"),
      description: params[:description],
      color: params[:color] || "#6B7280",
      rank: params.require(:rank).to_i
    )

    severity.save_in_position!
    redirect_to settings_severities_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_severities_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    if @severity.update(name: params[:name], description: params[:description], color: params[:color])
      redirect_to settings_severities_path
    else
      redirect_back fallback_location: settings_severities_path, inertia: { errors: @severity.errors.to_hash }
    end
  end

  def disable
    @severity.update!(deleted_at: Time.current)
    redirect_to settings_severities_path
  end

  def enable
    @severity.update!(deleted_at: nil)
    redirect_to settings_severities_path
  end

  def destroy
    if @severity.incidents.exists?
      return redirect_to settings_severities_path, alert: "Can't delete a severity that's in use by incidents. Disable it instead."
    end

    @severity.destroy!
    redirect_to settings_severities_path
  end

  private

  def set_severity
    @severity = current_workspace.incident_severities.find(params[:id])
  end
end
