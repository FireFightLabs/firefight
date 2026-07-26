class IntegrationsController < InertiaController
  before_action :require_authentication
  before_action :require_admin!, except: :index
  before_action :set_integration, only: [ :sync, :toggle_tool, :destroy ]

  def index
    render inertia: "integrations/index", props: {
      integrations: IntegrationSerializer.many(
        current_workspace.integrations.active.order(:name)
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
    rescue Integrations::McpClient::Error
      environment_row.record_health!(false)
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

  def destroy
    @integration.update!(deleted_at: Time.current)
    redirect_to integrations_path
  end

  private

  def set_integration
    @integration = current_workspace.integrations.active.find(params[:id])
  end

  def environment_options
    type = current_workspace.catalog_types.find_by(system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT)
    return [] unless type

    type.catalog_entries.active.order(:name).map { |entry| { id: entry.id, name: entry.name, slug: entry.slug } }
  end
end
