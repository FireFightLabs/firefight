class LimitCodeAgentQuestionsPerSession < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :questions_asked, :integer, default: 0, null: false
    add_index :code_agent_questions, :code_agent_session_id, unique: true, where: "status = 'open'", name: "index_code_agent_questions_one_open"

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE code_agent_sessions SET questions_asked = asked.count
          FROM (SELECT code_agent_session_id, COUNT(*) AS count FROM code_agent_questions GROUP BY code_agent_session_id) AS asked
          WHERE asked.code_agent_session_id = code_agent_sessions.id
        SQL
      end
    end
  end
end
