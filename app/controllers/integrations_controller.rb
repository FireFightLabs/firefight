class IntegrationsController < InertiaController
  class NameTaken < StandardError; end

  before_action :require_authentication
  before_action :require_admin!, except: :index
  before_action :set_integration,
                only: [ :sync, :toggle_tool, :set_all_tools, :toggle, :retarget_environment, :destroy ]

  def index
    render inertia: "integrations/index", props: {
      integrations: IntegrationSerializer.many(
        current_workspace.integrations.where(deleted_at: nil).order(:name)
                         .includes(:tools, integration_environments: :environment)
      ),
      providers: IntegrationProviderSerializer.many(IntegrationProvider.all),
      categories: IntegrationProvider.categories,
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries),
      canManage: current_membership.admin_access?
    }
  end

  def create
    provider = IntegrationProvider.find(params[:provider]) || IntegrationProvider.find(Integration::PROVIDER_CUSTOM_MCP)
    kind = provider&.kind || Integration::KIND_MCP

    integration = current_workspace.integrations.create!(
      kind: kind,
      provider: provider&.key || params[:provider].to_s,
      name: params.require(:name),
      settings: settings_for(kind) { params.require(:server_url) }
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
    return redirect_to integrations_path, alert: tool.toggle_blocked_reason if tool.toggle_blocked_reason

    tool.update!(enabled: !tool.enabled?)
    redirect_to integrations_path
  end

  def set_all_tools
    @integration.set_all_tools!(
      ActiveModel::Type::Boolean.new.cast(params[:enabled]),
      reads_only: ActiveModel::Type::Boolean.new.cast(params[:reads_only])
    )
    redirect_to integrations_path
  end

  def toggle
    @integration.update!(disabled_at: @integration.disabled_at ? nil : Time.current)
    redirect_to integrations_path
  end

  # Narrowing an existing connection to one environment, or widening it back.
  # The credentials stay put. Only which environment they answer for moves.
  def retarget_environment
    requested = params[:environment_id].presence
    verified = environment_id_param
    if requested && verified.nil?
      return redirect_to integrations_path, alert: "That environment is not available in this workspace."
    end

    @integration.integration_environments.find(params[:environment_row_id]).update!(catalog_entry_id: verified)
    redirect_to integrations_path
  rescue ActiveRecord::RecordInvalid
    redirect_to integrations_path, alert: "This connection already has credentials for that environment."
  end

  # Full-page navigation (not an Inertia visit): hands the browser to the
  # provider's install or consent screen. Nothing is persisted until the
  # customer comes back authorized, so abandoning that screen leaves no
  # half-connected row behind.
  def oauth_start
    provider = IntegrationProvider.find(params[:provider].to_s)
    return redirect_to integrations_path, alert: "Unknown integration." if provider.nil?
    return native_install_start(provider) if provider.kind == Integration::KIND_NATIVE
    if provider.server_url.blank?
      return redirect_to integrations_path, alert: "One-click connect needs a hosted server for this integration. Connect with a token instead."
    end

    oauth = IntegrationProvider.oauth_client(provider.key)
    flow = Integrations::OauthClient.begin_flow(
      server_url: provider.server_url, redirect_uri: oauth_callback_integrations_url,
      client_id: oauth[:client_id]
    )
    session[:integration_oauth] = {
      "provider" => provider.key, "name" => params[:name].presence || provider.name,
      "environment_id" => environment_id_param,
      "state" => flow[:state], "verifier" => flow[:verifier],
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
    return native_install_callback(provider, pending) if provider.kind == Integration::KIND_NATIVE

    credentials = Integrations::OauthClient.exchange(
      token_endpoint: pending["token_endpoint"], code: params[:code].to_s,
      verifier: pending["verifier"], client_id: pending["client_id"],
      client_secret: IntegrationProvider.oauth_client(provider.key)[:client_secret],
      redirect_uri: oauth_callback_integrations_url, resource: provider.server_url
    )

    environment_row = connect!(provider, pending["name"], pending["environment_id"])
    environment_row.store_oauth!(credentials)
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    redirect_to integrations_path
  rescue Integrations::OauthClient::Error => e
    redirect_to integrations_path, alert: "Could not connect: #{e.message}"
  rescue NameTaken
    redirect_to integrations_path, alert: "Another connection already uses that name. Pick a different one."
  end

  def destroy
    @integration.update!(deleted_at: Time.current)
    redirect_to integrations_path
  end

  private

  # Install-first without OAuth discovery: the provider's app is installed on
  # the customer's account and the callback brings back an installation id,
  # not tokens. Server-to-server tokens are minted from it at call time.
  def native_install_start(provider)
    state = SecureRandom.hex(16)
    install_url = Integrations::NativePack.for(provider.key)&.install_url(state: state)
    if install_url.blank?
      return redirect_to integrations_path, alert: "One-click connect is not configured for this integration on this install."
    end

    session[:integration_oauth] = {
      "provider" => provider.key, "name" => params[:name].presence || provider.name,
      "environment_id" => environment_id_param, "state" => state
    }
    redirect_to install_url, allow_other_host: true
  end

  def native_install_callback(provider, pending)
    if params[:installation_id].blank?
      return redirect_to integrations_path, alert: "The installation did not complete. Try again."
    end

    environment_row = connect!(provider, pending["name"], pending["environment_id"])
    environment_row.store_installation!(params[:installation_id])
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    redirect_to integrations_path
  end

  # Keyed on the slug rather than the provider so one provider can back
  # several accounts (two AWS accounts, two PlanetScale orgs), each with its
  # own credentials and its own action keys. Reconnecting under the default
  # name revives the existing connection rather than colliding on its slug.
  # Separating environments is a different axis: one connection, one
  # IntegrationEnvironment per environment, grants scoped to it.
  def connect!(provider, name, environment_id)
    integration = current_workspace.integrations.find_or_initialize_by(slug: Integration.slug_for(name))
    raise NameTaken if integration.persisted? && integration.provider != provider.key

    integration.assign_attributes(
      kind: provider.kind, provider: provider.key, name: name,
      settings: settings_for(provider.kind) { provider.server_url },
      deleted_at: nil, disabled_at: nil
    )
    integration.save!
    integration.integration_environments.find_or_create_by!(catalog_entry_id: environment_id.presence)
  end

  def set_integration
    @integration = current_workspace.integrations.where(deleted_at: nil).find(params[:id])
  end

  # Native integrations execute through their pack, so only MCP kinds carry a
  # server URL. The block defers reading it, so a native connect never
  # demands a URL param it will not store.
  def settings_for(kind)
    kind == Integration::KIND_NATIVE ? {} : { "server_url" => yield }
  end

  # Arrives on a full-page URL, so it is confirmed to be one of this
  # workspace's environments before it can bind credentials to a catalog entry.
  def environment_id_param
    id = params[:environment_id].presence
    id if id && current_workspace.environment_entries.exists?(id: id)
  end
end
