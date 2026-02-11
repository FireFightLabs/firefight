class AddWorkflowStateTimestamps < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :state_timestamps, :jsonb, null: false, default: {}
  end
end
