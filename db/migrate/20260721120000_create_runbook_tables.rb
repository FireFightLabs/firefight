class CreateRunbookTables < ActiveRecord::Migration[8.1]
  def change
    create_table :runbooks, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.string :summary
      t.text :content
      t.string :external_url
      t.integer :position, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :runbooks, [ :workspace_id, :slug ], unique: true

    create_table :runbook_steps, id: :uuid do |t|
      t.references :runbook, type: :uuid, null: false, foreign_key: true
      t.string :title, null: false
      t.text :instruction
      t.integer :position, null: false
      t.timestamps
    end

    create_table :incident_runbooks, id: :uuid do |t|
      t.references :incident, type: :uuid, null: false, foreign_key: true
      t.references :runbook, type: :uuid, null: false, foreign_key: true
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :attached_by, type: :uuid, null: true,
                   foreign_key: { to_table: :workspace_memberships }
      t.datetime :applied_at
      t.references :applied_by, type: :uuid, null: true,
                   foreign_key: { to_table: :workspace_memberships }
      t.string :message_ts
      t.timestamps
    end

    add_index :incident_runbooks, [ :incident_id, :runbook_id ], unique: true
  end
end
