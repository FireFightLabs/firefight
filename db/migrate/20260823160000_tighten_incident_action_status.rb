class TightenIncidentActionStatus < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE incident_actions SET status = 'open' WHERE status IS NULL"
    change_column_null :incident_actions, :status, false
  end

  def down
    change_column_null :incident_actions, :status, true
  end
end
