class CreateChatCustomSkills < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_custom_skills, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :source, null: false, default: "workspace"
      t.string :domain, null: false, default: "custom"
      t.uuid :live_version_id
      t.string :library_name
      t.integer :library_version
      t.jsonb :library_base
      t.integer :library_dismissed_version
      t.references :created_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.timestamps
      t.index [ :workspace_id, :name ], unique: true
    end

    create_table :chat_custom_skill_versions, id: :uuid do |t|
      t.references :custom_skill, type: :uuid, null: false, foreign_key: { to_table: :chat_custom_skills, on_delete: :cascade }, index: false
      t.integer :number, null: false
      t.string :status, null: false
      t.text :used_when, null: false
      t.string :tools, array: true, null: false, default: []
      t.text :steps, null: false
      t.string :references, array: true, null: false, default: []
      t.string :signals, array: true, null: false, default: []
      t.string :author_kind, null: false
      t.references :author, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.text :reason
      t.references :parent_version, type: :uuid, foreign_key: { to_table: :chat_custom_skill_versions, on_delete: :nullify }
      t.references :conversation, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :decided_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :decided_at
      t.datetime :told_at
      t.timestamps
      t.index [ :custom_skill_id, :number ], unique: true
      t.index :custom_skill_id, unique: true, where: "status = 'live'", name: "index_chat_custom_skill_versions_one_live"
      t.index [ :custom_skill_id, :status ]
    end
    add_foreign_key :chat_custom_skills, :chat_custom_skill_versions, column: :live_version_id, on_delete: :nullify
    add_index :chat_custom_skills, :live_version_id
  end
end
