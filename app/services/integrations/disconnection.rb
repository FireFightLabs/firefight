module Integrations
  # Removing the workspace's issue tracker, or a connection Firefight registered for map changes, takes back the webhook
  # Firefight registered while its credentials still reach the provider. What a person set up to send changes stays at
  # the provider, so removal says how to remove it. A connection made through an app installed at the provider also
  # removes the app from each account the person ticked, and installations says how each went.
  module Disconnection
    Result = Data.define(:removal, :installations)

    module_function

    def disconnect!(integration, uninstall:, by:)
      IssueSyncService.new(integration.workspace).connection_removed(integration, by: by)
      removal = integration.integration_environments.filter_map(&:live_updates_removal_words).uniq
      MapEvents.connection_removed(integration)
      installations = Installations.disconnected!(integration, uninstall: uninstall, by: by)
      integration.update!(deleted_at: Time.current)
      Result.new(removal: removal, installations: installations)
    end
  end
end
