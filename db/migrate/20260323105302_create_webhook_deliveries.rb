class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_deliveries, id: :uuid do |t|
      t.references :webhook, type: :uuid, null: false, foreign_key: true
      t.references :incident_event, type: :uuid, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :state, default: "pending", null: false
      t.jsonb :request_headers, default: {}
      t.jsonb :request_body, default: {}
      t.integer :response_code
      t.text :error_message
      t.datetime :delivered_at
      t.timestamps
    end

    add_index :webhook_deliveries, [ :webhook_id, :created_at ]
    add_index :webhook_deliveries, :created_at
  end
end
