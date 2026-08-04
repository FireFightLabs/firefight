module Workspace::CatalogueDefaults
  extend ActiveSupport::Concern

  DEFAULT_CATALOG_TYPES = [
    {
      name: "Team",
      slug: CatalogType::SYSTEM_KEY_TEAM,
      system_key: CatalogType::SYSTEM_KEY_TEAM,
      kind: CatalogType::KIND_SYSTEM,
      icon: "users",
      color: "#8B5CF6",
      description: "Teams that own and operate services",
      position: 1,
      attributes: [
        { slug: "description", name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 1 },
        { slug: "slack_channel", name: "Slack Channel", attribute_type: CatalogAttributeDefinition::TYPE_SLACK_CHANNEL, position: 2 },
        { slug: "manager", name: "Manager", attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER, position: 3 },
        { slug: "members", name: "Members", attribute_type: CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS, position: 4 }
      ]
    },
    {
      name: "Service",
      slug: CatalogType::SYSTEM_KEY_SERVICE,
      system_key: CatalogType::SYSTEM_KEY_SERVICE,
      kind: CatalogType::KIND_SYSTEM,
      icon: "server",
      color: "#3B82F6",
      description: "Services and applications in your infrastructure",
      position: 2,
      attributes: [
        { slug: "description", name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 1 },
        { slug: "owner_team", name: "Owner Team", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, position: 2, reference_system_key: CatalogType::SYSTEM_KEY_TEAM },
        { slug: "tier", name: "Tier", attribute_type: CatalogAttributeDefinition::TYPE_SELECT, position: 3, config: { "options" => [ "Critical", "Standard", "Internal" ] } },
        { slug: "repository", name: "Repository", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 4 },
        { slug: "slack_channel", name: "Slack Channel", attribute_type: CatalogAttributeDefinition::TYPE_SLACK_CHANNEL, position: 5 }
      ]
    },
    {
      name: "Environment",
      slug: CatalogType::SYSTEM_KEY_ENVIRONMENT,
      system_key: CatalogType::SYSTEM_KEY_ENVIRONMENT,
      kind: CatalogType::KIND_SYSTEM,
      icon: "cloud",
      color: "#10B981",
      description: "Deployment environments",
      position: 3,
      attributes: [
        { slug: "description", name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 1 },
        { slug: "is_production", name: "Is Production", attribute_type: CatalogAttributeDefinition::TYPE_BOOLEAN, position: 2 },
        { slug: "region", name: "Region", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 3 }
      ]
    },
    {
      name: "Functionality",
      slug: CatalogType::SYSTEM_KEY_FUNCTIONALITY,
      system_key: CatalogType::SYSTEM_KEY_FUNCTIONALITY,
      kind: CatalogType::KIND_SYSTEM,
      icon: "puzzle",
      color: "#F59E0B",
      description: "Business capabilities and product features",
      position: 4,
      attributes: [
        { slug: "description", name: "Description", attribute_type: CatalogAttributeDefinition::TYPE_TEXT, position: 1 },
        { slug: "owner_team", name: "Owner Team", attribute_type: CatalogAttributeDefinition::TYPE_REFERENCE, position: 2, reference_system_key: CatalogType::SYSTEM_KEY_TEAM }
      ]
    }
  ].freeze

  def setup_catalogue!
    transaction do
      create_default_catalog_types!
    end

    Rails.logger.info({
      event: "workspace.catalogue_defaults_created",
      message: "Created default catalogue configuration",
      workspace_id: id,
      types_count: DEFAULT_CATALOG_TYPES.size
    })
  end

  private

  def create_default_catalog_types!
    created_types = {}

    DEFAULT_CATALOG_TYPES.each do |type_data|
      next if catalog_types.exists?(system_key: type_data[:system_key])

      catalog_type = catalog_types.create!(type_data.except(:attributes))
      created_types[type_data[:system_key]] = catalog_type

      type_data[:attributes].each do |attr_data|
        config = attr_data.fetch(:config, {})

        if attr_data[:reference_system_key]
          referenced_type = created_types[attr_data[:reference_system_key]] ||
            catalog_types.find_by!(system_key: attr_data[:reference_system_key])
          config = config.merge("reference_type_id" => referenced_type.id)
        end

        catalog_type.catalog_attribute_definitions.create!(
          slug: attr_data[:slug],
          name: attr_data[:name],
          attribute_type: attr_data[:attribute_type],
          position: attr_data[:position],
          config: config
        )
      end
    end
  end
end
