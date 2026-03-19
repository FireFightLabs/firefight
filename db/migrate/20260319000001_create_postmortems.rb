class CreatePostmortems < ActiveRecord::Migration[8.1]
  def change
    create_table :postmortems, id: :uuid do |t|
      t.uuid :incident_id, null: false
      t.uuid :generated_by_id, null: false
      t.string :title, null: false
      t.text :summary
      t.jsonb :content, null: false, default: {}
      t.string :status, null: false, default: "draft"
      t.string :model_id
      t.string :message_ts
      t.timestamps

      t.index :incident_id, unique: true
    end

    add_foreign_key :postmortems, :incidents
    add_foreign_key :postmortems, :workspace_memberships, column: :generated_by_id

    create_table :postmortem_updates, id: :uuid do |t|
      t.uuid :postmortem_id, null: false
      t.uuid :incident_id, null: false
      t.uuid :edited_by_id, null: false
      t.string :update_type, null: false
      t.string :title, null: false
      t.text :summary
      t.jsonb :content, null: false, default: {}
      t.string :status, null: false
      t.jsonb :changed_sections, null: false, default: []
      t.string :model_id
      t.timestamps

      t.index [ :postmortem_id, :created_at ]
    end

    add_foreign_key :postmortem_updates, :postmortems
    add_foreign_key :postmortem_updates, :incidents
    add_foreign_key :postmortem_updates, :workspace_memberships, column: :edited_by_id
  end
end
