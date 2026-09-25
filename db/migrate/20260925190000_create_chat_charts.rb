# A chart a tool returned during a run or a chat, kept with the chat so the dashboard, the run's trace and Slack can draw
# what the tool saw at that moment. The series are the customer's data, so they are encrypted.
class CreateChatCharts < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_charts, id: :uuid do |t|
      t.references :chat, type: :uuid, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :tool_call_id, null: false
      # The run's step number, for a chart drawn in an investigation.
      t.integer :step_position
      t.integer :position, null: false, default: 0
      t.string :title, null: false
      t.string :unit
      t.string :source_url
      t.text :summary
      t.datetime :range_start, null: false
      t.datetime :range_end, null: false
      t.text :series, null: false
      t.datetime :created_at, null: false
      t.index [ :chat_id, :tool_call_id ]
    end
  end
end
