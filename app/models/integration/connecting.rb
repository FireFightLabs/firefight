# Connecting a provider under a name, keyed on the slug so one provider can back several accounts with their own
# credentials. Reconnecting under the default name revives the existing row. The region and the connect fields that are
# part of the server's address belong to the whole connection, so another environment cannot move it somewhere else.
# The other fields belong to the environment connected now, and a way of connecting that asks none leaves them as they
# were.
module Integration::Connecting
  extend ActiveSupport::Concern

  # Refused with the sentence to show on the form.
  class NameTaken < StandardError
    def initialize(message = "Another connection already uses that name. Pick a different one.") = super
  end

  class_methods do
    # The environment row the credentials are stored on.
    def connect!(workspace, provider, name, environment_id, region: nil, fields: nil, server_url: nil, kind: provider.kind, app: false)
      reserved = name_blocked_reason(name, workspace: workspace, provider: provider.key)
      raise NameTaken, reserved if reserved

      integration = workspace.integrations.find_or_initialize_by(slug: slug_for(name))
      raise NameTaken if integration.persisted? && integration.provider != provider.key

      path_values = provider.connect_values(fields, provider.address_fields)
      moved = integration.move_blocked_reason(provider.region(region), path_values, environment_id) if provider.regions.any? || path_values.any?
      raise NameTaken, moved if moved

      server_settings = kind == Integration::KIND_NATIVE ? {} : { "server_url" => server_url || provider.server_url_for(region, path_values) }
      integration.assign_attributes(
        kind: kind, provider: provider.key, name: name,
        settings: server_settings.merge({ Integration::REGION_SETTING => provider.region(region)&.key, Integration::FIELDS_SETTING => path_values.presence,
                                          Integration::APP_SETTING => (true if app) }.compact),
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
  end
end
