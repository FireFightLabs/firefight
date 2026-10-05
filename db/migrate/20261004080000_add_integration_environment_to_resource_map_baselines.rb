# A baseline remembers the connection that read it, so a platform and an observability tool reading the same resource
# each keep their own, and one connection's daily read replaces only its own. Until now only the connection that
# reports a resource read its baselines, so that is the one that read those already kept.
class AddIntegrationEnvironmentToResourceMapBaselines < ActiveRecord::Migration[8.1]
  def up
    add_reference :resource_map_baselines, :integration_environment, type: :uuid, index: true, foreign_key: { on_delete: :cascade }
    execute <<~SQL.squish
      UPDATE resource_map_baselines SET integration_environment_id = resource_map_resources.integration_environment_id
      FROM resource_map_resources WHERE resource_map_resources.id = resource_map_baselines.resource_id
    SQL
    remove_index :resource_map_baselines, %i[resource_id metric]
    add_index :resource_map_baselines, %i[resource_id integration_environment_id metric], unique: true,
                                                                                            name: "index_resource_map_baselines_on_resource_reader_metric"
  end

  def down
    remove_index :resource_map_baselines, name: "index_resource_map_baselines_on_resource_reader_metric"
    execute <<~SQL.squish
      DELETE FROM resource_map_baselines USING resource_map_resources
      WHERE resource_map_resources.id = resource_map_baselines.resource_id
        AND resource_map_baselines.integration_environment_id IS DISTINCT FROM resource_map_resources.integration_environment_id
    SQL
    add_index :resource_map_baselines, %i[resource_id metric], unique: true
    remove_reference :resource_map_baselines, :integration_environment, foreign_key: true
  end
end
