class CreateChatWatchUpdates < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_watch_updates, id: :uuid do |t|
      t.references :watch, type: :uuid, null: false, foreign_key: { to_table: :chat_watches, on_delete: :cascade }
      t.string :kind, null: false
      t.text :text, null: false
      t.datetime :told_at
      t.datetime :created_at, null: false
    end
  end
end
