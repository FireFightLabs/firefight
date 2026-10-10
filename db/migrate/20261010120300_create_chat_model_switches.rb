class CreateChatModelSwitches < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_model_switches, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :failed_model, null: false
      t.string :failed_provider
      t.string :backup_model, null: false
      t.string :backup_provider
      t.string :reason
      t.timestamps
    end
  end
end
