class AddChannelArchivedFieldsToIncidents < ActiveRecord::Migration[8.1]
  def change
    add_column :incidents, :channel_archived_at, :datetime
    add_column :incidents, :channel_archived_by, :string
  end
end
