class IntegrationsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!, except: :index
  before_action :set_integration, only: [ :sync, :toggle_tool, :toggle, :destroy ]

  def index
    render inertia: "integrations/index", props: {
      integrations: IntegrationSerializer.many(
        current_workspace.integrations.where(deleted_at: nil).order(:name)
                         .includes(:tools, integration_environments: :environment)
      ),
      providers: IntegrationProvider.all.map do |provider|
        { key: provider.key, name: provider.name, category: provider.category,
          mark: provider.mark, color: provider.color,
          description: provider.description, serverUrl: provider.server_url }
      end,
      environments: environment_options,
      canManage: current_membership.admin_access?
    }
  end

  def create
    provider = IntegrationProvider.find(params[:provider]) || IntegrationProvider.find(Integration::PROVIDER_CUSTOM_MCP)

    integration = current_workspace.integrations.create!(
      kind: Integration::KIND_MCP,
      provider: provider&.key || params[:provider].to_s,
      name: params.require(:name),
      settings: { "server_url" => params.require(:server_url) }
    )
    environment_row = integration.integration_environments.create!(
      catalog_entry_id: params[:environment_id].presence,
      credentials: params[:authorization].present? ? { "authorization" => params[:authorization] }.to_json : nil
    )

    begin
      Integrations::DiscoveryService.sync!(integration)
      Integrations::HealthCheckService.check!(environment_row)
    rescue Integrations::McpClient::Error => e
      environment_row.record_health!(false, error: e.message)
    end

    redirect_to integrations_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: integrations_path, inertia: { errors: e.record.errors.to_hash }
  end

  def sync
    Integrations::DiscoveryService.sync!(@integration)
    @integration.integration_environments.enabled.each { |row| Integrations::HealthCheckService.check!(row) }
    redirect_to integrations_path
  rescue Integrations::McpClient::Error => e
    redirect_to integrations_path, alert: "Could not reach the server: #{e.message}"
  end

  def toggle_tool
    tool = @integration.tools.find(params[:tool_id])
    tool.update!(enabled: !tool.enabled?)
    redirect_to integrations_path
  end

  def toggle
    @integration.update!(disabled_at: @integration.disabled_at ? nil : Time.current)
    redirect_to integrations_path
  end

  # Full-page navigation (not an Inertia visit): finds or creates the
  # pending connection, then hands the browser to the provider's consent
  # screen. PKCE state lives in the session until the callback.
  def oauth_start
    provider = IntegrationProvider.find(params[:provider].to_s)
    unless provider && provider.server_url.present?
      return redirect_to integrations_path, alert: "One-click connect needs a hosted server for this integration. Connect with a token instead."
    end

    # Start the flow BEFORE persisting anything, so a provider without
    # OAuth support (or a failed discovery) never leaves a broken connection
    # that would block reconnecting or hide the token path.
    oauth = IntegrationProvider.oauth_client(provider.key)
    flow = Integrations::OauthClient.begin_flow(
      server_url: provider.server_url, redirect_uri: oauth_callback_integrations_url,
      client_id: oauth[:client_id], client_secret: oauth[:client_secret]
    )

    # Reconnecting revives a previously disconnected connection rather than
    # colliding on its slug.
    integration = current_workspace.integrations.find_or_initialize_by(provider: provider.key)
    integration.assign_attributes(
      kind: Integration::KIND_MCP, name: provider.name,
      settings: { "server_url" => provider.server_url }, deleted_at: nil, disabled_at: nil
    )
    integration.save!
    environment_row = integration.integration_environments.first ||
                      integration.integration_environments.create!

    session[:integration_oauth] = {
      "environment_id" => environment_row.id, "state" => flow[:state], "verifier" => flow[:verifier],
      "client_id" => flow[:client_id], "client_secret" => flow[:client_secret],
      "token_endpoint" => flow[:token_endpoint], "resource" => provider.server_url
    }
    redirect_to flow[:authorize_url], allow_other_host: true
  rescue Integrations::OauthClient::Error => e
    redirect_to integrations_path, alert: "Could not start one-click connect: #{e.message}"
  end

  def oauth_callback
    pending = session.delete(:integration_oauth)
    unless pending.present? && params[:state].present? &&
           ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
      return redirect_to integrations_path, alert: "The connection attempt expired. Try again."
    end

    environment_row = IntegrationEnvironment.joins(:integration)
                                            .where(integrations: { workspace_id: current_workspace.id })
                                            .find(pending["environment_id"])
    token = Integrations::OauthClient.exchange(
      token_endpoint: pending["token_endpoint"], code: params[:code].to_s,
      verifier: pending["verifier"], client_id: pending["client_id"],
      client_secret: pending["client_secret"], redirect_uri: oauth_callback_integrations_url,
      resource: pending["resource"]
    )
    environment_row.update!(credentials: {
      "oauth" => token.merge(
        "token_endpoint" => pending["token_endpoint"],
        "client_id" => pending["client_id"],
        "client_secret" => pending["client_secret"],
        "resource" => pending["resource"]
      ).compact
    }.to_json)

    begin
      Integrations::DiscoveryService.sync!(environment_row.integration)
      Integrations::HealthCheckService.check!(environment_row)
    rescue Integrations::McpClient::Error => e
      environment_row.record_health!(false, error: e.message)
    end

    redirect_to integrations_path
  rescue Integrations::OauthClient::Error => e
    redirect_to integrations_path, alert: "Could not connect: #{e.message}"
  end

  def destroy
    @integration.update!(deleted_at: Time.current)
    redirect_to integrations_path
  end

  private

  def set_integration
    @integration = current_workspace.integrations.where(deleted_at: nil).find(params[:id])
  end

  def environment_options
    type = current_workspace.catalog_types.find_by(system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT)
    return [] unless type

    type.catalog_entries.active.order(:name).map { |entry| { id: entry.id, name: entry.name, slug: entry.slug } }
  end
end
