# The paths a code host connection keeps out of the code changes Halon writes, as patterns. Empty, so any file may change,
# since every change arrives as a pull request a person reviews. Its own column, so connecting again never resets it.
class AddProtectedPathsToIntegrations < ActiveRecord::Migration[8.1]
  def change
    add_column :integrations, :protected_paths, :string, array: true, default: [], null: false
  end
end
