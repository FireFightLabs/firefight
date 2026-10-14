# A step a coding agent asked permission for, which Halon decides or hands to the person as a question. A question
# asked for a permission does not count as one of the agent's own, so one can be open beside the agent's.
class CreateCodeAgentPermissions < ActiveRecord::Migration[8.1]
  def change
    create_table :code_agent_permissions, id: :uuid do |t|
      t.references :code_agent_session, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :workspace, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.string :request_id, null: false
      t.string :agent_session_id
      t.string :permission, null: false
      t.text :asked, null: false
      t.text :steps
      t.string :status, null: false, default: "open"
      t.text :reason
      t.string :decided_by_type
      t.uuid :decided_by_id
      t.datetime :decided_at
      t.timestamps
      t.index [ :code_agent_session_id, :request_id ], unique: true, name: "index_code_agent_permissions_on_session_and_request"
    end

    add_reference :code_agent_questions, :code_agent_permission, type: :uuid, foreign_key: { on_delete: :cascade }, index: { unique: true }
    remove_index :code_agent_questions, :code_agent_session_id, name: "index_code_agent_questions_one_open", unique: true, where: "((status)::text = 'open'::text)"
    add_index :code_agent_questions, :code_agent_session_id, name: "index_code_agent_questions_one_open", unique: true,
                                                           where: "status = 'open' AND code_agent_permission_id IS NULL"
  end
end
