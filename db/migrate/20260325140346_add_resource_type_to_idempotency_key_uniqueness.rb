class AddResourceTypeToIdempotencyKeyUniqueness < ActiveRecord::Migration[8.1]
  def change
    remove_index :idempotency_keys, [ :workspace_id, :key ]
    add_index :idempotency_keys, [ :workspace_id, :resource_type, :key ], unique: true
  end
end
