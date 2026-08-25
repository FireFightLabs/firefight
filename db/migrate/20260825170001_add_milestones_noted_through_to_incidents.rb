class AddMilestonesNotedThroughToIncidents < ActiveRecord::Migration[8.1]
  def change
    add_column :incidents, :milestones_noted_through, :string
  end
end
