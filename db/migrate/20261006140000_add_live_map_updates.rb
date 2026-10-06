class AddLiveMapUpdates < ActiveRecord::Migration[8.1]
  def change
    change_table :integration_environments, bulk: true do |t|
      # The connection's own address for a provider's change events, and the secret they are signed with.
      t.string :map_events_token
      t.text :map_events_secret
      # A webhook Firefight registered with the provider itself, and when it lapses.
      t.string :map_events_webhook_id
      t.datetime :map_events_expires_at
      t.string :map_events_error
      t.datetime :map_events_received_at
      # Where the provider's change log was last read, for a provider Firefight polls.
      t.string :map_events_cursor
    end
    add_index :integration_environments, :map_events_token, unique: true

    create_table :resource_map_events, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :integration_environment, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :provider_event_id, null: false
      t.string :action, null: false
      t.jsonb :scope, null: false, default: {}
      t.string :scope_key, null: false
      t.datetime :happened_at, null: false
      t.datetime :received_at, null: false
      t.datetime :applied_at
      t.string :outcome
      t.timestamps
    end

    add_index :resource_map_events, %i[integration_environment_id provider_event_id], unique: true, name: "index_resource_map_events_once"
    add_index :resource_map_events, %i[integration_environment_id scope_key], where: "outcome IS NULL", name: "index_resource_map_events_waiting"
    add_index :resource_map_events, :received_at
  end
end
