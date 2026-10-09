class CreateRepositorySetups < ActiveRecord::Migration[8.1]
  def change
    create_table :repository_setups, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :integration, type: :uuid, null: false, foreign_key: true, index: false
      t.string :repository, null: false
      t.jsonb :services, null: false, default: []
      t.jsonb :env, null: false, default: {}
      t.jsonb :commands, null: false, default: []
      t.jsonb :notes, null: false, default: []
      t.string :derived_from
      t.datetime :derived_at
      t.datetime :edited_at
      t.timestamps
    end
    add_index :repository_setups, [ :integration_id, :repository ], unique: true
  end
end
