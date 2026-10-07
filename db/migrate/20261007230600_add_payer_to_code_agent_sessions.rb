class AddPayerToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :paid_by, :string
    add_reference :code_agent_sessions, :workspace_ai_account, type: :uuid, foreign_key: { on_delete: :nullify }
  end
end
