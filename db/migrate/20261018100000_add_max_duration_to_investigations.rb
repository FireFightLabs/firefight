# A run concludes within a time it was given when it started, so a stuck one ends saying why rather than holding its
# incident. Runs from before have none.
class AddMaxDurationToInvestigations < ActiveRecord::Migration[8.1]
  def change
    add_column :investigations, :max_duration_seconds, :integer
  end
end
