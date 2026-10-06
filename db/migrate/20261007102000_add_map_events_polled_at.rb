class AddMapEventsPolledAt < ActiveRecord::Migration[8.1]
  def change
    # When Firefight last read the provider's change log for this connection, so each provider is read as often as it says.
    add_column :integration_environments, :map_events_polled_at, :datetime
  end
end
