class LetAChatMakeRoom < ActiveRecord::Migration[8.1]
  # A long run fills the model's window. Old tool results are moved into saved results, and when
  # that is not enough the old messages stop being sent. Nothing is deleted, so a run can still be
  # replayed and read back whole.
  def change
    add_column :chat_messages, :archived_at, :datetime
    add_column :chat_saved_results, :step, :integer

    create_table :chat_compactions, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true
      t.string :stage, null: false
      t.integer :tokens_before, null: false
      t.integer :tokens_freed, null: false, default: 0
      t.integer :messages_affected, null: false, default: 0
      t.text :note
      t.timestamps
    end
  end
end
