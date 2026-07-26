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
    integration.integration_environments.create!(
      catalog_entry_id: params[:environment_id].presence,
      credentials: params[:authorization].present? ? { "authorization" => params[:authorization] }.to_json : nil
    )
    Integrations::ConnectionRefresh.run!(integration)

    redirect_to integrations_path
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: integrations_path, inertia: { errors: e.record.errors.to_hash }
  end

  def sync
    Integrations::ConnectionRefresh.run!(@integration)
    redirect_to integrations_path
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

  # Full-page navigation (not an Inertia visit): hands the browser to the
  # provider's install or consent screen. Nothing is persisted until the
  # customer comes back authorized, so abandoning that screen leaves no
  # half-connected row behind.
  def oauth_start
    provider = IntegrationProvider.find(params[:provider].to_s)
    if provider.nil? || provider.server_url.blank?
      return redirect_to integrations_path, alert: "One-click connect needs a hosted server for this integration. Connect with a token instead."
    end

    oauth = IntegrationProvider.oauth_client(provider.key)
    flow = Integrations::OauthClient.begin_flow(
      server_url: provider.server_url, redirect_uri: oauth_callback_integrations_url,
      client_id: oauth[:client_id], app_slug: oauth[:app_slug], scopes: provider.scopes
    )
    session[:integration_oauth] = {
      "provider" => provider.key, "state" => flow[:state], "verifier" => flow[:verifier],
      "client_id" => flow[:client_id], "token_endpoint" => flow[:token_endpoint]
    }
    redirect_to flow[:authorize_url], allow_other_host: true
  rescue Integrations::OauthClient::Error => e
    redirect_to integrations_path, alert: "Could not start one-click connect: #{e.message}"
  end

  def oauth_callback
    pending = session.delete(:integration_oauth)
    provider = IntegrationProvider.find(pending["provider"]) if pending.present?
    unless provider && params[:state].present? &&
           ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
      return redirect_to integrations_path, alert: "The connection attempt expired. Try again."
    end

    credentials = Integrations::OauthClient.exchange(
      token_endpoint: pending["token_endpoint"], code: params[:code].to_s,
      verifier: pending["verifier"], client_id: pending["client_id"],
      client_secret: IntegrationProvider.oauth_client(provider.key)[:client_secret],
      redirect_uri: oauth_callback_integrations_url, resource: provider.server_url
    )

    environment_row = connect!(provider)
    environment_row.store_oauth!(credentials, installation_id: params[:installation_id])
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    redirect_to integrations_path
  rescue Integrations::OauthClient::Error => e
    redirect_to integrations_path, alert: "Could not connect: #{e.message}"
  end

  def destroy
    @integration.update!(deleted_at: Time.current)
    redirect_to integrations_path
  end

  private

  # Reconnecting revives a previously disconnected connection rather than
  # colliding on its slug.
  def connect!(provider)
    integration = current_workspace.integrations.find_or_initialize_by(provider: provider.key)
    integration.assign_attributes(
      kind: Integration::KIND_MCP, name: provider.name,
      settings: { "server_url" => provider.server_url }, deleted_at: nil, disabled_at: nil
    )
    integration.save!
    integration.integration_environments.first || integration.integration_environments.create!
  end

  def set_integration
    @integration = current_workspace.integrations.where(deleted_at: nil).find(params[:id])
  end

  def environment_options
    type = current_workspace.catalog_types.find_by(system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT)
    return [] unless type

    type.catalog_entries.active.order(:name).map { |entry| { id: entry.id, name: entry.name, slug: entry.slug } }
  end
end
