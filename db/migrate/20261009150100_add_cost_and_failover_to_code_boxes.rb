# Each box's size, price by the hour and seconds run, the provider that refused it when it started on the backup, and
# the token an address can carry in its query, kept encrypted apart from it.
class AddCostAndFailoverToCodeBoxes < ActiveRecord::Migration[8.1]
  def change
    change_table :code_boxes, bulk: true do |t|
      t.string :size
      t.bigint :hourly_micros
      t.integer :running_seconds, null: false, default: 0
      t.datetime :box_started_at
      t.string :failed_over_from
      t.text :failover_reason
      t.text :address_query
    end
    add_index :code_boxes, :created_at, where: "failed_over_from IS NOT NULL", name: "index_code_boxes_failovers"
  end
end
