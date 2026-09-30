class AddDetailToResourceMapChanges < ActiveRecord::Migration[8.1]
  def change
    # Which setting moved, for a change to how a resource is configured, such as its WAF custom rules.
    add_column :resource_map_changes, :detail, :string
  end
end
