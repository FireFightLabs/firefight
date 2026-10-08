# Moves a secret for a person between their connections through the gateway, so neither the value nor a way around a
# grant ever reaches Halon (Integrations::SecretHandoffs says how a tool asks for one). Nothing here keeps a value.
module Integration::SecretHandoff
  Handoffs = Integrations::SecretHandoffs

  # The value a reference names, read live from its connection as principal, who must be allowed the tool that made it.
  # The read is ledgered under that tool, with the reference and never the value.
  def self.resolve(text, workspace:, principal:, source:)
    reference = Handoffs.parse(text)
    tool, environment_row = located(reference, workspace)
    authorized(tool, environment_row, principal: principal, source: source, params: { Handoffs::REFERENCE => text.to_s.strip }) do
      value = Integrations::NativePack.fetch!(tool.integration).secret_value(environment_row: environment_row, path: reference.path)
      raise Handoffs::Unresolved, "#{tool.integration.display_name} no longer has what the reference names." if value.blank?

      value
    end
  rescue AbilityGateway::Denied
    raise Handoffs::Unresolved, "#{principal.try(:display_name) || 'This caller'} may not use #{tool.integration.display_name}'s " \
                                "#{tool.name}, so what it made cannot be read for them."
  end

  # Sends a value the person typed where the tool's target says, as principal, who must still be allowed the tool that
  # asked for it. Answers what the pack said it did. The ledger keeps the target, never the value.
  def self.fill!(tool:, catalog_entry_id:, target:, value:, principal:, source:)
    Handoffs.checked!(value)
    environment_row = tool.integration.resolve_environment(catalog_entry_id)
    raise Handoffs::Unresolved, "#{tool.integration.display_name} is no longer connected for that environment." unless environment_row

    authorized(tool, environment_row, principal: principal, source: source, params: target.to_h) do
      Integrations::NativePack.fetch!(tool.integration).fill_secret(environment_row: environment_row, target: target.to_h, value: value)
    end
  end

  # A call that named value_from is done at once, inside the call the gateway already allowed. The value is read where
  # the reference says, as the same person, and sent. Any other answer comes back unchanged.
  def self.settle(result, tool:, environment_row:, principal:, workspace:, source: AbilityGateway::SOURCE_CONVERSATION)
    entry = Handoffs.entry_of(result)
    return result unless entry && entry[Handoffs::VALUE_FROM].present?

    value = resolve(entry[Handoffs::VALUE_FROM], workspace: workspace, principal: principal, source: source)
    Handoffs.checked!(value)
    said = Integrations::NativePack.fetch!(tool.integration).fill_secret(environment_row: environment_row, target: entry[Handoffs::TARGET].to_h, value: value)
    Integrations::Telemetry.result("#{said} The value came from #{entry[Handoffs::VALUE_FROM]} and was never shown.", link: nil)
  end

  def self.located(reference, workspace)
    integration = workspace.integrations.find_by(id: reference.integration_id)
    raise Handoffs::Unresolved, "The connection the reference names is not in this workspace any more." unless integration

    tool = integration.tools.enabled.available.find_by(name: reference.tool_name)
    raise Handoffs::Unresolved, "#{integration.display_name}'s #{reference.tool_name} is switched off, so what it made cannot be read." unless tool

    environment_row = integration.resolve_environment(reference.catalog_entry_id)
    raise Handoffs::Unresolved, "#{integration.display_name} is no longer connected for that environment." unless environment_row

    [ tool, environment_row ]
  end

  # holdable: false, since an approval rule over the tool held the call that made or asked for the secret, and this is
  # its second half.
  def self.authorized(tool, environment_row, principal:, source:, params:, &)
    scope = environment_row.catalog_entry_id ? { "environment" => environment_row.catalog_entry_id } : {}
    AbilityGateway.authorize!(principal: principal, action_key: tool.action_key, workspace: tool.integration.workspace, scope: scope,
                              params: params, context: { source: source }, holdable: false, &)
  end
  private_class_method :located, :authorized
end
