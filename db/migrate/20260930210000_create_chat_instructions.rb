class CreateChatInstructions < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_instructions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true, index: false
      t.references :scope, type: :uuid, polymorphic: true
      t.text :text, null: false
      t.references :added_by, type: :uuid, foreign_key: { to_table: :workspace_memberships, on_delete: :nullify }
      t.datetime :superseded_at
      t.references :superseded_by, type: :uuid, foreign_key: { to_table: :chat_instructions, on_delete: :nullify }
      t.timestamps
    end
    add_index :chat_instructions, %i[workspace_id superseded_at]
  end
end
