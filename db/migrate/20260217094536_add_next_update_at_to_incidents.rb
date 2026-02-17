class AddNextUpdateAtToIncidents < ActiveRecord::Migration[8.1]
  def change
    add_column :incidents, :next_update_at, :datetime
  end
end
