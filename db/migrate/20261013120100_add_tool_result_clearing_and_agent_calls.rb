# This once shared its version with another migration, so a database may already have these columns under that one.
class AddToolResultClearingAndAgentCalls < ActiveRecord::Migration[8.1]
  def change
    add_column :code_agent_sessions, :tool_result_clearing, :jsonb, default: {}, null: false, if_not_exists: true
    add_column :inferences, :agent_call, :jsonb, if_not_exists: true
  end
end
