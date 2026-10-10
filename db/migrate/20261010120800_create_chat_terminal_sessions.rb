class CreateChatTerminalSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_terminal_sessions, id: :uuid do |t|
      t.references :workspace, type: :uuid, null: false, foreign_key: true
      t.references :owner, polymorphic: true, type: :uuid, null: false
      t.references :principal, polymorphic: true, type: :uuid
      t.boolean :changes_allowed, null: false, default: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :closed_at
      t.integer :calls, null: false, default: 0
      t.timestamps
    end
    add_index :chat_terminal_sessions, :token_digest, unique: true
  end
end
