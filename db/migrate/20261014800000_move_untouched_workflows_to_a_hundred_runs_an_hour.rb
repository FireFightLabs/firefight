# Workflows made before most runs per hour defaulted to 100 hold the old default of 60. Nothing recorded whether an
# admin chose a value, so exactly 60 is read as untouched and moves to 100, and any other value stays as it was set.
class MoveUntouchedWorkflowsToAHundredRunsAnHour < ActiveRecord::Migration[8.1]
  OLD_DEFAULT = 60
  NEW_DEFAULT = 100

  def up
    execute "UPDATE workflows SET runs_per_hour = #{NEW_DEFAULT}, updated_at = now() WHERE runs_per_hour = #{OLD_DEFAULT}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Which workflows were moved is not kept."
  end
end
