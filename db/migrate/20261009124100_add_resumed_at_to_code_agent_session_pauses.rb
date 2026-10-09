class AddResumedAtToCodeAgentSessionPauses < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_session_pauses, :resumed_at, :datetime
  end
end
