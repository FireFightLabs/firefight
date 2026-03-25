class CreateIdempotencyKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :idempotency_keys, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :resource_type, null: false
      t.uuid :resource_id, null: false
      t.datetime :created_at, null: false
    end

    add_index :idempotency_keys, [ :workspace_id, :key ], unique: true
    add_index :idempotency_keys, :created_at
  end
end
