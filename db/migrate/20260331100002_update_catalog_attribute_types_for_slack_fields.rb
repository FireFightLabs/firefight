class UpdateCatalogAttributeTypesForSlackFields < ActiveRecord::Migration[8.1]
  UPDATES = {
    "team" => {
      "slack_channel" => "slack_channel",
      "manager" => "workspace_member",
      "members" => "workspace_members"
    },
    "service" => {
      "slack_channel" => "slack_channel"
    }
  }.freeze

  def up
    UPDATES.each do |system_key, attr_changes|
      CatalogType.where(system_key: system_key).find_each do |catalog_type|
        attr_changes.each do |attr_key, new_type|
          CatalogAttributeDefinition
            .where(catalog_type: catalog_type, key: attr_key)
            .update_all(attribute_type: new_type)
        end
      end
    end
  end

  def down
    UPDATES.each do |system_key, attr_changes|
      CatalogType.where(system_key: system_key).find_each do |catalog_type|
        attr_changes.each do |attr_key, _new_type|
          old_type = attr_key == "members" ? "list" : "text"
          CatalogAttributeDefinition
            .where(catalog_type: catalog_type, key: attr_key)
            .update_all(attribute_type: old_type)
        end
      end
    end
  end
end
