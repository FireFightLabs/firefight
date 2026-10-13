class AddRepairProblemKeyToWorkflows < ActiveRecord::Migration[8.1]
  def change
    # The failure Halon last suggested a fix for, so the same failure again costs nothing.
    add_column :workflows, :repair_problem_key, :string
  end
end
