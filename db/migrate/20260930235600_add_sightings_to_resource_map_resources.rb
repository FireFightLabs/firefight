class AddSightingsToResourceMapResources < ActiveRecord::Migration[8.1]
  def change
    # Each connection that reports a resource, by its environment row id, with the details it reported.
    add_column :resource_map_resources, :sightings, :jsonb, default: {}, null: false
  end
end
