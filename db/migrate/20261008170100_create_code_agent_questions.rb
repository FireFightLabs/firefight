# A question a coding agent asks while it writes a change, and its answer, from Halon or the person the change is for.
class CreateCodeAgentQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :code_agent_questions, id: :uuid do |t|
      t.references :code_agent_session, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.text :question, null: false
      t.text :answer
      t.string :status, null: false, default: "open"
      t.string :answered_by_type
      t.uuid :answered_by_id
      t.datetime :answer_due_at, null: false
      t.datetime :answered_at
      t.string :message_channel_id
      t.string :message_id
      t.timestamps
    end
  end
end
