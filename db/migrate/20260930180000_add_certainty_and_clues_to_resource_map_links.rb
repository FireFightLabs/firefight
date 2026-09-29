class AddCertaintyAndCluesToResourceMapLinks < ActiveRecord::Migration[8.1]
  def change
    add_column :resource_map_links, :certainty, :string
    add_column :resource_map_links, :clues, :jsonb, null: false, default: []
  end
end
