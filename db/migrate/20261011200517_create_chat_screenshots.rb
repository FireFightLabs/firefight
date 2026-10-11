class CreateChatScreenshots < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_screenshots, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, foreign_key: true, index: false
      t.string :tool_call_id
      t.references :remediation_step, type: :uuid, foreign_key: { to_table: :investigation_remediation_steps, on_delete: :nullify }
      t.integer :position, null: false, default: 0
      t.integer :step_position
      t.string :viewport, null: false
      t.text :page_url
      t.text :title
      t.integer :stopped_step
      t.text :would_send
      t.string :check_digest
      t.integer :byte_size, null: false, default: 0
      t.timestamps
    end
    add_index :chat_screenshots, [ :chat_id, :tool_call_id ]
  end
end
