class AddToolResultClearingAndAgentCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :tool_result_clearing, :jsonb, default: {}, null: false
    add_column :inferences, :agent_call, :jsonb
  end
end
