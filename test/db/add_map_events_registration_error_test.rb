require "test_helper"
require Rails.root.join("db/migrate/20261021090000_add_map_events_registration_error")

class AddMapEventsRegistrationErrorTest < ActiveSupport::TestCase
  test "a confirmation asked with the old words reads the new ones, and an old Event Grid failure no longer says the activity log is off" do
    integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "azure", name: "Azure", slug: "azure")
    old_words, new_words = AddMapEventsRegistrationError::REWORDED.first
    asked = integration.integration_environments.create!(map_events_confirmation: old_words,
                                                         map_events_error: "The service principal may not subscribe. Give it the EventGrid EventSubscription Contributor role")
    polled = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, map_events_error: "Azure answered 403: AuthorizationFailed")
    migration = AddMapEventsRegistrationError.new

    migration.send(:reword, AddMapEventsRegistrationError::REWORDED)
    migration.send(:clear_event_grid_failures)

    assert_equal [ new_words, nil ], asked.reload.values_at(:map_events_confirmation, :map_events_error)
    assert_equal Integrations::MapEventSources::Azure::CONFIRMATION, new_words
    assert_equal "Azure answered 403: AuthorizationFailed", polled.reload.map_events_error, "a reason the log could not be read stays"
  end
end
