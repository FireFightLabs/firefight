class AlertSourcesController < InertiaController
  before_action :require_authentication
  before_action :set_alert_source, only: [ :update, :destroy, :token, :sample_payload ]

  def create
    source = current_workspace.alert_sources.new(
      name: params.dig(:alert_source, :name),
      provider: params.dig(:alert_source, :provider).presence || AlertSource::PROVIDER_GENERIC
    )

    if source.save
      redirect_to settings_alert_sources_path
    else
      redirect_back fallback_location: settings_alert_sources_path, inertia: { errors: source.errors.to_hash }
    end
  end

  def update
    attrs = { name: params.dig(:alert_source, :name), enabled: params.dig(:alert_source, :enabled) }.compact
    attrs[:config] = updated_config

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

  # The secret is fetched on demand (copy button), never embedded in page
  # props, mirroring how API keys avoid shipping credentials on every render.
  def token
    render json: { token: @alert_source.secret_token }
  end

  # The most recent raw payload, so the field-mapping UI can offer real keys
  # to click instead of asking users to type paths blind.
  def sample_payload
    alert = @alert_source.alerts.order(received_at: :desc).first
    render json: { payload: alert&.payload }
  end

  private

  def set_alert_source
    @alert_source = current_workspace.alert_sources.find(params[:id])
  end

  def updated_config
    config = @alert_source.config.dup
    source_params = params.fetch(:alert_source, {})

    config["severity_map"] = severity_map if source_params[:severity_map]
    config["field_map"] = field_map if source_params.key?(:field_map)
    config["items_path"] = source_params[:items_path].presence if source_params.key?(:items_path)
    if source_params.key?(:fingerprint_fields)
      config["fingerprint_fields"] = Array(source_params[:fingerprint_fields]).map { |f| f.to_s.strip }.reject(&:empty?).presence
    end
    if source_params[:flap_window_minutes].present?
      config["flap_window_minutes"] = source_params[:flap_window_minutes].to_i.clamp(AlertSource::FLAP_WINDOW_MINUTES_RANGE.min, AlertSource::FLAP_WINDOW_MINUTES_RANGE.max)
    end

    config.compact
  end

  # Only known normalized fields are mappable; paths are free-form dot-paths.
  def field_map
    raw = params.dig(:alert_source, :field_map).to_unsafe_h

    raw.each_with_object({}) do |(field, path), map|
      next unless AlertProviders::Base::NORMALIZED_FIELDS.include?(field.to_s)

      map[field.to_s] = path.to_s.strip if path.to_s.strip.present?
    end
  end

  # {"critical" => severity_id}; keys are free-form provider strings, values
  # must be severities of this workspace.
  def severity_map
    raw = params.dig(:alert_source, :severity_map).to_unsafe_h
    valid_ids = current_workspace.incident_severities.pluck(:id).to_set

    raw.each_with_object({}) do |(key, value), map|
      map[key.to_s.downcase] = value if valid_ids.include?(value)
    end
  end
end
