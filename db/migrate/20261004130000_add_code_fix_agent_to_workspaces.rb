class AddCodeFixAgentToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    # The slug of the connected coding agent that writes a fix's code changes. Empty while Firefight's own agent does.
    add_column :workspaces, :code_fix_agent, :string
  end
end
