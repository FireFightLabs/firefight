class HardenWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :webhook_deliveries, :signed_payload, :text
    add_column :webhook_deliveries, :attempts, :integer, default: 0, null: false
    add_index  :webhook_deliveries, :state
  end
end
