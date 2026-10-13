class AddPrivateInputsToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :private_inputs, :text
    add_column :workflow_runs, :private_inputs, :text
  end
end
