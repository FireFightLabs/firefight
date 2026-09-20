# The columns a run and a hypothesis carried when each theory went to its own sub-agent. One agent holds
# the whole investigation now, and nothing has written these since.
class DropSubAgentLeftovers < ActiveRecord::Migration[8.1]
  def change
    remove_column :investigations, :tool_set, :jsonb, default: [], null: false
    remove_column :investigation_hypotheses, :specialist, :string
    remove_column :investigation_hypotheses, :max_turns, :integer
  end
end
