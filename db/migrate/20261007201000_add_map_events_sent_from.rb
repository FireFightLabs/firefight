class AddMapEventsSentFrom < ActiveRecord::Migration[8.1]
  def change
    # Where a setup the person made at the provider has sent changes from, such as an AWS region, with when it last did.
    add_column :integration_environments, :map_events_sent_from, :jsonb, default: {}, null: false
  end
end
