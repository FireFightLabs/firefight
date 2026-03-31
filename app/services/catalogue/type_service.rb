module Catalogue
  class TypeService
    def initialize(workspace)
      @workspace = workspace
    end

    def create(name:, description: nil, icon: nil, color: nil, attribute_definitions: [])
      CatalogType.transaction do
        next_position = @workspace.catalog_types.maximum(:position).to_i + 1

        type = @workspace.catalog_types.create!(
          name: name,
          slug: CatalogType.generate_slug(name),
          kind: CatalogType::KIND_CUSTOM,
          description: description,
          icon: icon,
          color: color,
          position: next_position
        )

        type.sync_attribute_definitions!(attribute_definitions) if attribute_definitions.present?
        type
      end
    end

    def update(type, attrs:, attribute_definitions: nil)
      CatalogType.transaction do
        type.update!(attrs)
        type.sync_attribute_definitions!(attribute_definitions) if attribute_definitions.present?
        type
      end
    end

    def delete(type)
      type.soft_delete!
    end
  end
end
