class IntegrationsController < InertiaController
  include ReturnTo

  authorizes Ability::Action::RESOURCE_INTEGRATIONS,
    read: :index,
    create: %i[create oauth_start oauth_callback list_scopes],
    update: %i[sync toggle_tool mark_tool_read set_all_tools toggle retarget_environment choose edit_field scope_options scopes map_events_secret forget_map_events_secrets live_updates
               live_updates_setup protected_paths make_map_events_secret],
    delete: :destroy
  before_action :set_integration,
                only: [ :sync, :toggle_tool, :mark_tool_read, :set_all_tools, :toggle, :retarget_environment, :choose, :edit_field, :scope_options, :scopes, :map_events_secret,
                      :forget_map_events_secrets, :make_map_events_secret,
                      :live_updates, :live_updates_setup, :protected_paths, :destroy ]
  # Connecting leaves for the provider and comes back here, setup or not.
  skip_before_action :continue_setup, only: %i[oauth_start oauth_callback]

  def index
    render inertia: "integrations/index", props: {
      integrations: IntegrationSerializer.many(
        current_workspace.integrations.connections.where(deleted_at: nil).order(:name)
                         .includes(:tools, :repository_setups, integration_environments: :environment)
      ),
      providers: IntegrationProviderSerializer.many(IntegrationProvider.connectable),
      categories: IntegrationProvider.categories,
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries)
    }
  end

  def create
    # A test login is saved from its own screen (TestLoginsController), never connected from here.
    provider = IntegrationProvider.find(params[:provider]).then { |entry| entry unless entry&.test_logins } ||
               IntegrationProvider.find(Integration::PROVIDER_CUSTOM_MCP)
    return connect_with_url(provider) if provider&.connection_url? && params.key?(:connection_url)
    # A provider connected with credentials may offer its own MCP server instead, which the token form reaches.
    return connect_with_credentials(provider) if provider&.api_token? && (params.key?(:credentials) || !provider.mcp_alternative?)

    # A database connected from a URL can also be reached through an MCP server the team runs.
    kind = provider.nil? || provider.connection_url? || provider.mcp_alternative? ? Integration::KIND_MCP : provider.kind
    reserved = Integration.name_blocked_reason(params.require(:name), workspace: current_workspace, provider: provider&.key || params[:provider].to_s)
    return redirect_back(fallback_location: integrations_path, alert: reserved) if reserved

    # The server's whole address is pasted here, so only the fields that are not part of it are asked, and none when it
    # is a native provider's own MCP server.
    asked = provider&.mcp_alternative? ? [] : provider&.environment_fields.to_a
    refusal = provider&.connect_refusal(nil, fields_param(provider), asked) || token_refusal(provider)
    return redirect_back(fallback_location: integrations_path, alert: refusal) if refusal

    integration = current_workspace.integrations.create!(
      kind: kind,
      provider: provider&.key || params[:provider].to_s,
      name: params.require(:name),
      settings: settings_for(kind) { params.require(:server_url) }
    )
    environment_row = integration.integration_environments.create!(
      catalog_entry_id: params[:environment_id].presence,
      credentials: IntegrationEnvironment.token_credentials(authorization_param(provider), header: provider&.token&.header)
    )
    environment_row.store_fields!(provider.connect_values(fields_param(provider), asked)) if asked.any?
    Integrations::ConnectionRefresh.run!(integration)

    connected(integration.name, return_to_param)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: integrations_path, inertia: { errors: e.record.errors.to_hash }
  end

  def sync
    return redirect_to integrations_path, notice: "#{@integration.name}'s tools were refreshed." if Integrations::ConnectionRefresh.run!(@integration)

    redirect_to integrations_path, alert: "#{@integration.name} could not be reached, so its tools were not refreshed. The connection says why."
  end

  def toggle_tool
    tool = @integration.tools.find(params[:tool_id])
    return redirect_to integrations_path, alert: tool.toggle_blocked_reason if tool.toggle_blocked_reason

    tool.update!(enabled: !tool.enabled?)
    Integrations::ConnectionRefresh.tools_changed(@integration)
    redirect_to integrations_path, notice: "#{tool.name} on #{@integration.name} is #{tool.enabled? ? 'on' : 'off'}."
  end

  # An admin marks a tool of a server Firefight cannot know as a read, or takes the mark away.
  def mark_tool_read
    tool = @integration.tools.find(params[:tool_id])
    read = ActiveModel::Type::Boolean.new.cast(params[:read])
    blocked = tool.mark_read_blocked_reason(read)
    return redirect_to integrations_path, alert: blocked if blocked

    tool.mark_read!(read)
    said = read ? "is marked as a read, so Halon calls it without asking" : "is no longer marked as a read, so Halon asks before calling it"
    redirect_to integrations_path, notice: "#{tool.name} on #{@integration.name} #{said}."
  end

  def set_all_tools
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    reads_only = ActiveModel::Type::Boolean.new.cast(params[:reads_only])
    @integration.set_all_tools!(enabled, reads_only: reads_only)
    Integrations::ConnectionRefresh.tools_changed(@integration)
    redirect_to integrations_path, notice: all_tools_notice(enabled, reads_only)
  end

  def toggle
    @integration.update!(disabled_at: @integration.disabled_at ? nil : Time.current)
    redirect_to integrations_path, notice: "#{@integration.name} is #{@integration.disabled_at ? 'off' : 'on'}."
  end

  # Moves which environment the connection answers for. The credentials stay put.
  def retarget_environment
    requested = params[:environment_id].presence
    verified = environment_id_param
    if requested && verified.nil?
      return redirect_to integrations_path, alert: "That environment is not available in this workspace."
    end

    row = @integration.integration_environments.find(params[:environment_row_id])
    row.update!(catalog_entry_id: verified)
    redirect_to integrations_path, notice: "#{@integration.name} now answers for #{row.environment&.name || 'every environment'}."
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

  # Changes a field asked on the connect form that the provider lets a person change afterwards, such as a token's id,
  # and checks the connection again with it at once.
  def edit_field
    row = @integration.integration_environments.find(params[:environment_row_id])
    field = IntegrationProvider.find(@integration.provider)&.editable_fields&.find { |each| each.key == params[:key].to_s }
    return redirect_to integrations_path, alert: "#{@integration.name} has no such setting to change." unless field

    refusal = row.edit_field!(field, params[:value])
    return redirect_to integrations_path, alert: refusal if refusal

    Integrations::ConnectionRefresh.run!(@integration)
    said = row.reload.fields[field.key].present? ? "saved" : "cleared"
    redirect_to integrations_path, notice: "#{@integration.name}'s #{field.label.downcase_first} was #{said}."
  end

  # What the credentials typed on the connect form can read, such as a token's projects, listed before anything is saved
  # so the form offers them. The credentials go no further than the provider.
  def list_scopes
    provider = IntegrationProvider.find(params[:provider].to_s)
    return render(json: { options: [], error: "#{params[:provider]} chooses nothing to read." }, status: :unprocessable_entity) unless provider&.scope_field

    values = params.fetch(:credentials, {}).permit(*Integrations::Credentials.fields_for(provider.key).map(&:key)).to_h
    fields = provider.connect_values(fields_param(provider), provider.environment_fields.reject(&:scope))
    render json: scope_listing { Integrations::Credentials.scope_options(provider.key, values, region: provider.region(params[:region].presence), fields: fields) }
  end

  # What a connection's credentials can read now, for choosing again what it reads.
  def scope_options
    row = @integration.integration_environments.find(params[:environment_row_id])
    render json: scope_listing { Integrations::ConnectionSettings.of(row).scope_options }
  end

  # Chooses again what a connection reads at its provider, such as which projects, and reads it again at once.
  def scopes
    row = @integration.integration_environments.find(params[:environment_row_id])
    field = IntegrationProvider.find(@integration.provider)&.scope_field
    return redirect_to integrations_path, alert: "#{@integration.name} chooses nothing to read." unless field

    refusal = row.choose_scopes!(field, params[:values])
    return redirect_to integrations_path, alert: refusal if refusal

    Integrations::ConnectionRefresh.run!(@integration)
    settings = Integrations::ConnectionSettings.of(row.reload)
    named = settings.all_scopes? ? settings.chosen_scopes : settings.chosen_scopes.map { |id| settings.scope_name(id) }
    redirect_to integrations_path, notice: "#{@integration.name} now reads #{field.reach_words(named)}."
  end

  # The paths Halon may not change in the repositories a code host connection holds. A refusal stays on the form beside
  # what was typed, and the connection's details stay open either way.
  def protected_paths
    details = integrations_path(Integration::DETAILS_QUERY_PARAM => @integration.id)
    refusal = @integration.protect_paths!(params[:paths])
    return redirect_to details, inertia: { errors: { paths: refusal } } if refusal

    redirect_to details, notice: "Saved. #{@integration.protected_paths_words}"
  end

  # The signing secret an admin pasted from a provider set up by hand to send its changes to the connection's address.
  def map_events_secret
    row = @integration.integration_environments.find(params[:environment_row_id])
    return redirect_to integrations_path, alert: "#{@integration.name} is not set up by hand to send its changes." unless row.map_events_set_up_by_hand?
    return redirect_to integrations_path, alert: "Paste the signing secret #{@integration.name} shows for its webhook." if params[:secret].to_s.strip.empty?

    row.save_map_events_secret!(params[:secret])
    return redirect_to integrations_path, notice: "Signing secret saved. #{row.map_events_saved_words}" unless row.map_event_source.many_secrets?

    saved = "#{row.map_events_secrets.size} signing #{'secret'.pluralize(row.map_events_secrets.size)}"
    redirect_to integrations_path, notice: "Signing secret added. #{@integration.name} now has #{saved} saved, and a change signed with any one reaches the map."
  end

  # A signing secret Firefight makes for a provider that takes whatever secret its webhook is given, shown once.
  def make_map_events_secret
    row = @integration.integration_environments.find(params[:environment_row_id])
    return redirect_to integrations_path, alert: "Firefight does not make a signing secret for #{@integration.name}." unless row.map_events_secret_made?

    replaced = row.map_events_secret_set?
    flash.inertia[:map_events_signing_secret] = row.make_map_events_secret!
    said = replaced ? "replaced. The old one stopped working" : "made"
    redirect_to integrations_path, notice: "#{@integration.name}'s signing secret was #{said}. Copy the new one now, since it is shown once."
  end

  # Forgets every signing secret saved for a provider whose webhooks each sign with their own, so an admin can start over.
  def forget_map_events_secrets
    row = @integration.integration_environments.find(params[:environment_row_id])
    blocked = row.forget_map_events_secrets_blocked_reason
    return redirect_to integrations_path, alert: blocked if blocked

    row.forget_map_events_secrets!
    redirect_to integrations_path, notice: "Signing secrets forgotten. Changes #{@integration.name} sends no longer reach the map until you add a secret again."
  end

  # Turns live updates on or off for one connection, once the person confirmed what it does to the provider's account.
  def live_updates
    row = @integration.integration_environments.find(params[:environment_row_id])
    on = ActiveModel::Type::Boolean.new.cast(params[:on])
    blocked = on ? row.live_updates_turn_on_blocked_reason : row.live_updates_turn_off_blocked_reason
    return redirect_to integrations_path, alert: blocked if blocked

    on ? turn_live_updates_on(row) : turn_live_updates_off(row)
  end

  # A full-page navigation to the provider. Nothing is persisted until the customer
  # returns authorized, so abandoning it leaves no half-connected row.
  def oauth_start
    provider = IntegrationProvider.find(params[:provider].to_s)
    return redirect_to integrations_path, alert: "Unknown integration." if provider.nil?

    return app_start(provider) if ActiveModel::Type::Boolean.new.cast(params[:app]) && provider.app_connect?

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
      "return_to" => return_to_param, "workspace_id" => current_workspace.id
    }
    redirect_to flow[:authorize_url], allow_other_host: true
  rescue Integrations::OauthFlow::Error => e
    redirect_to integrations_path, alert: Integrations::Sentence.join("Could not start one-click connect", e)
  end

  def oauth_callback
    pending = session.delete(:integration_oauth)
    provider = IntegrationProvider.find(pending["provider"]) if pending.present?
    unless provider && params[:state].present? &&
           ActiveSupport::SecurityUtils.secure_compare(pending["state"].to_s, params[:state].to_s)
      return redirect_to integrations_path, alert: "The connection attempt expired. Try again."
    end
    # The browser may have moved to another workspace while it was away.
    unless pending["workspace_id"] == current_workspace.id
      return redirect_to integrations_path, alert: "This connection was started in another workspace, so nothing was connected. Start it again here."
    end
    return app_callback(provider, pending) if pending["app"] && provider.app_connect?

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
    redirect_to integrations_path, alert: Integrations::Sentence.join("Could not connect", e)
  rescue Integration::NameTaken => e
    redirect_to integrations_path, alert: e.message
  end

  # Opens the provider's own page that sets one place up to send changes as they happen, with the connection's address and
  # secret filled in. A redirect, so the secret is never in a page Firefight renders.
  def live_updates_setup
    row = @integration.integration_environments.find(params[:environment_row_id])
    blocked = row.live_updates_setup_blocked_reason(params[:place].to_s)
    return redirect_to integrations_path, alert: blocked if blocked

    # The link is built from the place the provider offers, never from what was asked, so it only leads to its own pages.
    offered = row.live_updates_offer.places.find { |each| each.place == params[:place].to_s }
    redirect_to row.live_updates_setup_link(offered.place), allow_other_host: true
  end

  # The toast says how to remove what a person set up at the provider, and links to the app's settings for an app left
  # installed there (Integrations::Disconnection).
  def destroy
    result = Integrations::Disconnection.disconnect!(@integration, uninstall: params[:uninstall], by: current_membership)
    removal = result.removal
    installations = result.installations
    return redirect_to integrations_path, notice: "Disconnected #{@integration.name}." if removal.empty? && installations.empty?

    lead = removal.any? ? "#{@integration.name} is disconnected and Firefight no longer accepts the changes it sends." : "#{@integration.name} is disconnected."
    failed, done = installations.partition(&:error)
    flash.inertia[:links] = installations.filter_map(&:link)
    flash[:alert] = failed.map(&:words).join(" ") if failed.any?
    redirect_to integrations_path, notice: [ lead, *removal, *done.map(&:words) ].join(" ")
  end

  private

  def turn_live_updates_on(row)
    Integrations::MapEvents.turn_on!(row)
    state = row.reload.live_updates
    return redirect_to integrations_path, notice: row.live_updates_switched_words(on: true) if state.on && row.map_events_webhook_id.present?

    redirect_to integrations_path, alert: row.live_updates_turn_on_failed_words
  end

  def turn_live_updates_off(row)
    Integrations::MapEvents.turn_off!(row)
    redirect_to integrations_path, notice: row.live_updates_switched_words(on: false)
  rescue Integrations::Error => error
    redirect_to integrations_path, alert: row.live_updates_turn_off_failed_words(error)
  end

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
  rescue Integration::NameTaken => e
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
  rescue Integration::NameTaken => e
    redirect_back fallback_location: integrations_path, inertia: { errors: { name: e.message } }
  end

  # Firefight's own app with a provider reached through its MCP server, which connects it natively, or through the MCP
  # server itself where the server takes the app's token (IntegrationProvider::App#mcp). Like any OAuth, nothing is kept
  # until the person comes back authorized.
  def app_start(provider)
    flow = Integrations::OauthFlow.begin_app(provider, redirect_uri: oauth_callback_integrations_url)
    session[:integration_oauth] = {
      "provider" => provider.key, "name" => params[:name].presence || provider.app_connection_name, "environment_id" => environment_id_param,
      "state" => flow[:state], "verifier" => flow[:verifier], "client_id" => flow[:client_id], "token_endpoint" => flow[:token_endpoint],
      "app" => true, "return_to" => return_to_param, "workspace_id" => current_workspace.id
    }
    redirect_to flow[:authorize_url], allow_other_host: true
  end

  # A workspace with no other tracker keeps its items in step with the connection made by an app that is its provider's
  # one way in, so nobody has to choose it.
  def app_callback(provider, pending)
    credentials = Integrations::OauthFlow.exchange_app(provider, pending, code: params[:code].to_s, redirect_uri: oauth_callback_integrations_url)
    environment_row = connect!(provider, pending["name"], pending["environment_id"], kind: provider.app.kind, app: true)
    environment_row.store_oauth!(credentials)
    integration = environment_row.integration
    Integrations::ConnectionRefresh.run!(integration)
    return connected(integration.name, safe_return_to(pending["return_to"])) unless provider.app_only?

    chosen = IssueSyncService.new(current_workspace).choose_sole_tracker!(integration, by: current_membership)
    redirect_to safe_return_to(pending["return_to"]) || integrations_path, notice: [ "#{integration.name} is connected.", chosen ].compact.join(" ")
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
      "environment_id" => environment_id_param, "state" => state, "return_to" => return_to_param, "workspace_id" => current_workspace.id
    }
    redirect_to install_url, allow_other_host: true
  end

  def native_install_callback(provider, pending)
    if params[:installation_id].blank?
      return redirect_to integrations_path, alert: "The installation did not complete. Try again."
    end
    refusal = Integrations::Credentials.installation_refusal(provider.key, params[:installation_id].to_s, code: params[:code].to_s,
                                                                                                        redirect_uri: oauth_callback_integrations_url)
    return redirect_to integrations_path, alert: refusal if refusal

    environment_row = connect!(provider, pending["name"], pending["environment_id"])
    Integrations::Installations.connected!(environment_row, params[:installation_id])
    Integrations::ConnectionRefresh.run!(environment_row.integration)

    connected(environment_row.integration.name, safe_return_to(pending["return_to"]))
  end

  # Connecting from a chat or the setup checklist goes back there.
  def connected(name, return_to)
    redirect_to return_to || integrations_path, notice: "#{name} is connected."
  end

  def all_tools_notice(enabled, reads_only)
    return "Every tool on #{@integration.name} is off." unless enabled
    return "Only the tools on #{@integration.name} that read are on." if reads_only

    "Every tool on #{@integration.name} is on."
  end

  def connect!(provider, name, environment_id, **options)
    Integration.connect!(current_workspace, provider, name, environment_id, **options)
  end

  # The token form's values, for a provider whose credential is fields (IntegrationProvider::TokenForm).
  def token_fields_param(provider)
    params.fetch(:token_fields, {}).permit(*provider.token.fields.map(&:key)).to_h
  end

  # The header the connection is reached with: built from the token form's fields where the provider names them, and
  # otherwise as pasted, which a header sent whole still is.
  def authorization_param(provider)
    token_fields?(provider) ? provider.token.authorization(token_fields_param(provider)) : params[:authorization]
  end

  def token_refusal(provider)
    provider.token.refusal(token_fields_param(provider)) if token_fields?(provider)
  end

  def token_fields?(provider) = provider&.token&.fields? && params[:authorization].blank?

  # What the connect form asked beside the credentials, only the fields the provider declares.
  def fields_param(provider)
    return {} unless provider

    params.fetch(:fields, {}).permit(*provider.connect_fields.map { |field| field.multiple ? { field.key => [] } : field.key }).to_h
  end

  # A listing as the form reads it, or the provider's words when it would not list.
  def scope_listing
    { options: yield.map(&:to_h), error: nil }
  rescue Integrations::Error => error
    { options: [], error: error.message }
  end

  # The activity log says which tool was marked and which way, beside the request it binds an approval to.
  def web_authorization_params
    return super unless action_name == "mark_tool_read"

    tool = current_workspace.integrations.where(deleted_at: nil).find_by(id: params[:id])&.tools&.find_by(id: params[:tool_id])
    super.merge({ "tool" => tool&.name, "read" => ActiveModel::Type::Boolean.new.cast(params[:read]) }.compact)
  end

  def set_integration
    @integration = current_workspace.integrations.connections.where(deleted_at: nil).find(params[:id])
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
