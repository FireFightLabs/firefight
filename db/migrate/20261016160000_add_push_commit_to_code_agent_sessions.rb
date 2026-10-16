class AddPushCommitToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :push_commit, :string
  end
end
