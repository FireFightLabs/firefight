class IntegrationsController < InertiaController
  class NameTaken < StandardError
    def initialize(message = "Another connection already uses that name. Pick a different one.") = super
  end

  authorizes Ability::Action::RESOURCE_INTEGRATIONS,
    read: :index,
    create: %i[create oauth_start oauth_callback],
    update: %i[sync toggle_tool set_all_tools toggle retarget_environment choose],
    delete: :destroy
  before_action :set_integration,
                only: [ :sync, :toggle_tool, :set_all_tools, :toggle, :retarget_environment, :choose, :destroy ]

  def index
    render inertia: "integrations/index", props: {
      integrations: IntegrationSerializer.many(
        current_workspace.integrations.where(deleted_at: nil).order(:name)
                         .includes(:tools, integration_environments: :environment)
      ),
      providers: IntegrationProviderSerializer.many(IntegrationProvider.all),
      categories: IntegrationProvider.categories,
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries)
    }
  end

  def create
    provider = IntegrationProvider.find(params[:provider]) || IntegrationProvider.find(Integration::PROVIDER_CUSTOM_MCP)
    return connect_with_url(provider) if provider&.connection_url? && params.key?(:connection_url)
    # A provider connected with credentials may offer its own MCP server instead, which the token form reaches.
    return connect_with_credentials(provider) if provider&.api_token? && (params.key?(:credentials) || !provider.mcp_alternative?)

    # A database connected from a URL can also be reached through an MCP server the team runs.
    kind = provider.nil? || provider.connection_url? || provider.mcp_alternative? ? Integration::KIND_MCP : provider.kind
    reserved = Integration.name_blocked_reason(params.require(:name))
    return redirect_back(fallback_location: integrations_path, alert: reserved) if reserved

    # The server's whole address is pasted here, so only the fields that are not part of it are asked, and none when it
    # is a native provider's own MCP server.
    asked = provider&.mcp_alternative? ? [] : provider&.environment_fields.to_a
    refusal = provider&.connect_refusal(nil, fields_param(provider), asked)
    return redirect_back(fallback_location: integrations_path, alert: refusal) if refusal

    integration = current_workspace.integrations.create!(
      kind: kind,
      provider: provider&.key || params[:provider].to_s,
      name: params.require(:name),
      settings: settings_for(kind) { params.require(:server_url) }
    )
    environment_row = integration.integration_environments.create!(
      catalog_entry_id: params[:environment_id].presence,
      credentials: params[:authorization].present? ? { "authorization" => params[:authorization] }.to_json : nil
    )
    environment_row.store_fields!(provider.connect_values(fields_param(provider), asked)) if asked.any?
    Integrations::ConnectionRefresh.run!(integration)

    connected(integration.name, return_to_param)
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
    Integrations::ConnectionRefresh.tools_changed(@integration)
    redirect_to integrations_path
  end

  def set_all_tools
    @integration.set_all_tools!(
      ActiveModel::Type::Boolean.new.cast(params[:enabled]),
      reads_only: ActiveModel::Type::Boolean.new.cast(params[:reads_only])
    )
    Integrations::ConnectionRefresh.tools_changed(@integration)
    redirect_to integrations_path
  end

  def toggle
    @integration.update!(disabled_at: @integration.disabled_at ? nil : Time.current)
    redirect_to integrations_path
  end

  # Moves which environment the connection answers for. The credentials stay put.
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

  # Chooses a value the connection learned to choose from, such as which of several datasources holds its logs.
  def choose
    row = @integration.integration_environments.find(params[:environment_row_id])
    field = IntegrationProvider.find(@integration.provider)&.learned_fields&.find { |each| each.key == params[:key].to_s }
    return redirect_to integrations_path, alert: "#{@integration.name} has no such choice." unless field

    refusal = row.choose!(field, params[:value])
    return redirect_to integrations_path, alert: refusal if refusal

    redirect_to integrations_path, notice: "#{@integration.name} now uses #{field.shown(row.fields[field.key], choices: field.options_from(row.learned))} for #{field.label.downcase_first}."
  end

  # A full-page navigation to the provider. Nothing is persisted until the customer
  # returns authorized, so abandoning it leaves no half-connected row.
  def oauth_start
    provider = IntegrationProvider.find(params[:provider].to_s)
    return redirect_to integrations_path, alert: "Unknown integration." if provider.nil?

    kind = provider.connect_kind(params[:kind])
    return native_install_start(provider) if kind == Integration::KIND_NATIVE
    if provider.server_url.blank?
      return redirect_to integrations_path, alert: "One-click connect needs a hosted server for this integration. Connect with a token instead."
    end

    asked = provider.asked_fields(kind)
    refusal = provider.connect_refusal(params[:region].presence, fields_param(provider), asked)
    return redirect_to integrations_path, alert: refusal if refusal

    region = provider.region(params[:region].presence)&.key

    name = params[:name].presence || provider.name
    server_url = Integration.server_url_for(current_workspace, provider, name, region, provider.connect_values(fields_param(provider), asked), kind: kind)
    flow = Integrations::OauthFlow.begin(provider, redirect_uri: oauth_callback_integrations_url, server_url: server_url, region: region)
    session[:integration_oauth] = {
      "provider" => provider.key, "name" => name,
      "environment_id" => environment_id_param,
      "state" => flow[:state], "verifier" => flow[:verifier],
      "client_id" => flow[:client_id], "token_endpoint" => flow[:token_endpoint],
      "server_url" => server_url, "region" => region, "fields" => provider.connect_values(fields_param(provider), asked), "kind" => kind,
      "return_to" => return_to_param
    }
    redirect_to flow[:authorize_url], allow_other_host: true
  rescue Integrations::OauthFlow::Error => e
    redirect_to integrations_path, alert: "Could not start one-click connect: #{e.message}"
  end

  def oauth_callback
    pending = session.delete(:integration_oauth)
    provider = IntegrationProvider.find(pending["provider"]) if pending.present?
    unless provider && params[:state].present? &&
           ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
      return redirect_to integrations_path, alert: "The connection attempt expired. Try again."
    end
    kind = provider.connect_kind(pending["kind"])
    return native_install_callback(provider, pending) if kind == Integration::KIND_NATIVE

    credentials = Integrations::OauthFlow.exchange(
      provider, pending, code: params[:code].to_s, redirect_uri: oauth_callback_integrations_url
    )

    environment_row = connect!(provider, pending["name"], pending["environment_id"], region: pending["region"], fields: pending["fields"],
                                                                                    server_url: pending["server_url"], kind: kind)
    environment_row.store_oauth!(credentials)
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    connected(environment_row.integration.name, safe_return_to(pending["return_to"]))
  rescue Integrations::OauthFlow::Error => e
    redirect_to integrations_path, alert: "Could not connect: #{e.message}"
  rescue NameTaken => e
    redirect_to integrations_path, alert: e.message
  end

  def destroy
    @integration.update!(deleted_at: Time.current)
    redirect_to integrations_path
  end

  private

  # The same name connects another environment, or replaces the URL of one already connected. The URL is checked before
  # anything is saved, so a mistyped or private address is said on the form.
  def connect_with_url(provider)
    url = params[:connection_url].to_s
    certificates = params.fetch(:certificates, {}).permit(*Integrations::Credentials.certificate_fields(provider.key)).to_h
    refusal = Integrations::Credentials.url_refusal(provider.key, url, certificates)
    return redirect_back(fallback_location: integrations_path, inertia: { errors: { connection: refusal } }) if refusal

    environment_row = connect!(provider, params.require(:name), environment_id_param)
    Integrations::Credentials.store_url!(environment_row, url: url, certificates: certificates)
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    connected(environment_row.integration.name, return_to_param)
  rescue NameTaken => e
    redirect_back fallback_location: integrations_path, inertia: { errors: { name: e.message } }
  end

  # Like a URL, the same name connects another environment or replaces its credentials. The pack checks the values with
  # the provider before anything is saved, so a wrong token is said on the form.
  def connect_with_credentials(provider)
    values = params.fetch(:credentials, {}).permit(*Integrations::Credentials.fields_for(provider.key).map(&:key)).to_h
    region = params[:region].presence
    fields = provider.connect_values(fields_param(provider), provider.environment_fields)
    refusal = provider.connect_refusal(region, fields_param(provider), provider.environment_fields) ||
              Integrations::Credentials.refusal(provider.key, values, region: provider.region(region), fields: fields)
    return redirect_back(fallback_location: integrations_path, inertia: { errors: { connection: refusal } }) if refusal

    environment_row = connect!(provider, params.require(:name), environment_id_param, region: region, fields: fields)
    Integrations::Credentials.store!(environment_row, values)
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    connected(environment_row.integration.name, return_to_param)
  rescue NameTaken => e
    redirect_back fallback_location: integrations_path, inertia: { errors: { name: e.message } }
  end

  # The callback brings back an installation id, not tokens. Server-to-server tokens are minted from it at call time.
  def native_install_start(provider)
    state = SecureRandom.hex(16)
    install_url = Integrations::Credentials.install_url(provider.key, state: state)
    if install_url.blank?
      return redirect_to integrations_path, alert: "One-click connect is not configured for this integration on this install."
    end

    session[:integration_oauth] = {
      "provider" => provider.key, "name" => params[:name].presence || provider.name,
      "environment_id" => environment_id_param, "state" => state, "return_to" => return_to_param
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

    connected(environment_row.integration.name, safe_return_to(pending["return_to"]))
  end

  # Connecting from a chat goes back to that chat and says so there. From this page nothing changes.
  def connected(name, return_to)
    return redirect_to(integrations_path) unless return_to

    redirect_to return_to, notice: "#{name} is connected."
  end

  def return_to_param = safe_return_to(params[:return_to])

  # Only a chat on this dashboard, so a crafted link cannot send someone elsewhere after they connect.
  def safe_return_to(path)
    path = path.to_s
    return nil unless path.start_with?("/") && !path.start_with?("//")

    route = Rails.application.routes.recognize_path(path)
    path if route[:controller] == AgentChatsController.controller_path && %w[index show].include?(route[:action])
  rescue ActionController::RoutingError
    nil
  end

  # Keyed on the slug so one provider can back several accounts with their own credentials.
  # Reconnecting under the default name revives the existing row. The region and the connect fields that are part of the
  # server's address belong to the whole connection, so another environment cannot move it somewhere else. The other
  # fields belong to the environment connected now, and a way of connecting that asks none leaves them as they were.
  def connect!(provider, name, environment_id, region: nil, fields: nil, server_url: nil, kind: provider.kind)
    slug = Integration.slug_for(name)
    reserved = Integration.name_blocked_reason(name)
    raise NameTaken, reserved if reserved

    integration = current_workspace.integrations.find_or_initialize_by(slug: slug)
    raise NameTaken if integration.persisted? && integration.provider != provider.key

    path_values = provider.connect_values(fields, provider.address_fields)
    moved = integration.move_blocked_reason(provider.region(region), path_values, environment_id) if provider.regions.any? || path_values.any?
    raise NameTaken, moved if moved

    integration.assign_attributes(
      kind: kind, provider: provider.key, name: name,
      settings: settings_for(kind) { server_url || provider.server_url_for(region, path_values) }
                  .merge({ Integration::REGION_SETTING => provider.region(region)&.key, Integration::FIELDS_SETTING => path_values.presence }.compact),
      deleted_at: nil, disabled_at: nil
    )
    integration.save!
    environment_row = integration.integration_environments.find_or_create_by!(catalog_entry_id: environment_id.presence)
    if fields && kind == provider.kind && provider.environment_fields.any?
      chosen = environment_row.fields.slice(*provider.learned_fields.map(&:key))
      environment_row.store_fields!(chosen.merge(provider.connect_values(fields, provider.environment_fields)))
    end
    environment_row
  end

  # What the connect form asked beside the credentials, only the fields the provider declares.
  def fields_param(provider)
    return {} unless provider

    params.fetch(:fields, {}).permit(*provider.connect_fields.map { |field| field.multiple ? { field.key => [] } : field.key }).to_h
  end

  def set_integration
    @integration = current_workspace.integrations.where(deleted_at: nil).find(params[:id])
  end

  # Only MCP kinds carry a server URL. The block defers reading it so a native connect never demands one.
  def settings_for(kind)
    kind == Integration::KIND_NATIVE ? {} : { "server_url" => yield }
  end

  # Arrives on a full-page URL, so it is checked against this workspace's environments before binding credentials.
  def environment_id_param
    id = params[:environment_id].presence
    id if id && current_workspace.environment_entries.exists?(id: id)
  end
end
