class RenamePostmortemUpdatesChangedSectionsToChangedFields < ActiveRecord::Migration[8.1]
  def change
    rename_column :postmortem_updates, :changed_sections, :changed_fields
  end
end
