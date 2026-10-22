require "test_helper"
require Rails.root.join("db/migrate/20261021090000_add_map_events_registration_error")

class AddMapEventsRegistrationErrorTest < ActiveSupport::TestCase
  test "a confirmation asked with the old words reads the new ones, and an old Azure registration failure no longer says the activity log is off" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    old_words, new_words = AddMapEventsRegistrationError::REWORDED.first
    asked = integration.integration_environments.create!(map_events_confirmation: old_words,
                                                         map_events_error: "The service principal may not subscribe. Give it the EventGrid EventSubscription Contributor role")
    unaddressed = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id,
                                                               map_events_error: "Firefight's own address is not set, so there is nowhere to send changes.")
    other = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render", slug: "render")
    refused = other.integration_environments.create!(map_events_error: "Render answered 400: webhook limit reached")
    migration = AddMapEventsRegistrationError.new

    migration.send(:reword, AddMapEventsRegistrationError::REWORDED)
    migration.send(:clear_registration_failures)

    assert_equal [ new_words, nil ], asked.reload.values_at(:map_events_confirmation, :map_events_error)
    assert_equal Integrations::MapEventSources::Azure::CONFIRMATION, new_words
    assert_nil unaddressed.reload.map_events_error, "any of Azure's registration failures, Event Grid named or not"
    assert_equal "Render answered 400: webhook limit reached", refused.reload.map_events_error, "a provider registered with only keeps its reason"
  end
end
