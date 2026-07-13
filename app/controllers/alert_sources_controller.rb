class AlertSourcesController < InertiaController
  before_action :require_authentication
  before_action :set_alert_source, only: [ :update, :destroy ]

  def create
    source = current_workspace.alert_sources.new(
      name: params.dig(:alert_source, :name),
      provider: AlertSource::PROVIDER_GENERIC
    )

    if source.save
      redirect_to settings_alert_sources_path
    else
      redirect_back fallback_location: settings_alert_sources_path, inertia: { errors: source.errors.to_hash }
    end
  end

  def update
    attrs = { name: params.dig(:alert_source, :name), enabled: params.dig(:alert_source, :enabled) }.compact
    attrs[:config] = @alert_source.config.merge("severity_map" => severity_map) if params.dig(:alert_source, :severity_map)

    if @alert_source.update(attrs)
      redirect_to settings_alert_sources_path
    else
      redirect_back fallback_location: settings_alert_sources_path, inertia: { errors: @alert_source.errors.to_hash }
    end
  end

  def destroy
    @alert_source.destroy!
    redirect_to settings_alert_sources_path
  end

  private

  def set_alert_source
    @alert_source = current_workspace.alert_sources.find(params[:id])
  end

  # {"critical" => severity_id} — keys are free-form provider strings, values
  # must be severities of this workspace.
  def severity_map
    raw = params.dig(:alert_source, :severity_map).to_unsafe_h
    valid_ids = current_workspace.incident_severities.pluck(:id).to_set

    raw.each_with_object({}) do |(key, value), map|
      map[key.to_s.downcase] = value if valid_ids.include?(value)
    end
  end
end
