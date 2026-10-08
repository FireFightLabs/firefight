class CreateChatWatches < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_watches, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :asker, type: :uuid, polymorphic: true, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "active"
      t.datetime :expires_at, null: false
      t.integer :usual_seconds
      t.string :limit_basis, null: false
      t.datetime :check_claimed_at
      t.datetime :checked_at
      t.text :outcome
      t.datetime :finished_at
      t.references :stopped_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :told_at
      t.timestamps
    end
    add_index :chat_watches, [ :workspace_id, :status ]
  end
end
