class AddMapEventsScopes < ActiveRecord::Migration[8.1]
  def change
    # What a registered webhook covers for a connection that reaches several projects or workspaces, so Firefight
    # registers again once the connection reaches others.
    add_column :integration_environments, :map_events_scopes, :jsonb
  end
end
