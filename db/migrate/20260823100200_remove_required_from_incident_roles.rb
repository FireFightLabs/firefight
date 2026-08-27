class RemoveRequiredFromIncidentRoles < ActiveRecord::Migration[8.1]
  def change
    remove_column :incident_roles, :required, :boolean, default: false
  end
end
