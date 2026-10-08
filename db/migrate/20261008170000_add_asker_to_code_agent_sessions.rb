# A coding agent reads connected systems as whoever asked for the change and asks them its questions, so its session
# names that principal, the box its run reads code in, and where the change was asked for.
class AddAskerToCodeAgentSessions < ActiveRecord::Migration[8.1]
  def change
    change_table :code_agent_sessions, bulk: true do |t|
      t.string :principal_type
      t.uuid :principal_id
      t.string :box_key
      t.string :place_type
      t.uuid :place_id
      t.string :tool_call_id
      t.integer :tool_calls, default: 0, null: false
    end
  end
end
