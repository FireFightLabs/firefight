# The built-in Service type always had a Repository attribute. It now carries the role an investigation reads.
class MarkWhereAServiceKeepsItsCode < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE catalog_attribute_definitions AS definition
      SET role = 'repository', updated_at = now()
      FROM catalog_types AS catalog_type
      WHERE definition.catalog_type_id = catalog_type.id
        AND catalog_type.system_key = 'service'
        AND definition.slug = 'repository'
        AND definition.attribute_type = 'text'
        AND definition.role IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM catalog_attribute_definitions AS taken
          WHERE taken.catalog_type_id = catalog_type.id AND taken.role = 'repository'
        )
    SQL
  end

  def down
    execute "UPDATE catalog_attribute_definitions SET role = NULL WHERE role = 'repository'"
  end
end
