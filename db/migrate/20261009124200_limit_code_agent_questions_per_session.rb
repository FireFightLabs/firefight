class LimitCodeAgentQuestionsPerSession < ActiveRecord::Migration[8.1]
  STATUS_OPEN = "open"
  STATUS_EXPIRED = "expired"

  def change
    add_column :code_agent_sessions, :questions_asked, :integer, default: 0, null: false

    # A session can already hold more than one open question, so all but its newest expire before the index forbids it.
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE code_agent_questions SET status = '#{STATUS_EXPIRED}', updated_at = now()
          WHERE status = '#{STATUS_OPEN}' AND id NOT IN (
            SELECT DISTINCT ON (code_agent_session_id) id FROM code_agent_questions
            WHERE status = '#{STATUS_OPEN}' ORDER BY code_agent_session_id, created_at DESC
          )
        SQL
      end
    end

    add_index :code_agent_questions, :code_agent_session_id, unique: true, where: "status = '#{STATUS_OPEN}'", name: "index_code_agent_questions_one_open"

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
