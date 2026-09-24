class KeepWhereARunReadsCode < ActiveRecord::Migration[8.1]
  def change
    create_table :code_boxes, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :key, null: false
      t.string :provider, null: false
      t.string :box_ref, null: false
      t.string :address, null: false
      t.string :secret, null: false
      t.jsonb :repositories, null: false, default: {}
      t.datetime :last_used_at, null: false
      t.datetime :stopped_at
      t.timestamps
    end
    add_index :code_boxes, :key, unique: true, where: "stopped_at IS NULL", name: "index_code_boxes_on_open_key"
    add_index :code_boxes, :last_used_at, where: "stopped_at IS NULL", name: "index_code_boxes_on_open_last_used"
  end
end
