class AddDetectedAtToIncidents < ActiveRecord::Migration[8.1]
  def change
    add_column :incidents, :detected_at, :datetime
    add_index :incidents, :detected_at

    add_column :incident_updates, :detected_at, :datetime
  end
end
