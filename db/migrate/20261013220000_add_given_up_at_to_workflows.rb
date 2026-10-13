# A scheduled time that was given up but whose giving up broke before it was recorded, so the next sweep records it and
# tells of it. The time itself stays given up.
class AddGivenUpAtToWorkflows < ActiveRecord::Migration[8.1]
  def change
    add_column :workflows, :given_up_at, :datetime
  end
end
