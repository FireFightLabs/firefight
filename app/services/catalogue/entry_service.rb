module Catalogue
  class EntryService
    def initialize(workspace)
      @workspace = workspace
    end

    def create(type:, name:, raw_attributes:)
      provisioned_attrs = provision_member_attributes(type, raw_attributes)

      CatalogEntry.transaction do
        entry = type.catalog_entries.new(
          workspace: @workspace,
          name: name,
          slug: CatalogType.generate_slug(name)
        )

        _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(provisioned_attrs)
        entry.save!
        entry.sync_references!(reference_attrs)
        entry
      end
    end

    def update(entry, name: nil, raw_attributes: {})
      provisioned_attrs = provision_member_attributes(entry.catalog_type, raw_attributes)

      CatalogEntry.transaction do
        entry.name = name if name.present?
        _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(provisioned_attrs)
        entry.save!
        entry.sync_references!(reference_attrs)
        entry
      end
    end

    def delete(entry)
      entry.soft_delete!
    end

    private

    def provision_member_attributes(type, raw_attrs)
      definitions = type.catalog_attribute_definitions.index_by(&:key)
      adapter = @workspace.adapter

      raw_attrs.each_with_object({}) do |(key, value), result|
        attr_def = definitions[key.to_s]
        unless attr_def
          result[key] = value
          next
        end

        case attr_def.attribute_type
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER
          result[key] = provision_single_member(value, adapter)
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS
          result[key] = provision_multiple_members(value, adapter)
        else
          result[key] = value
        end
      end
    end

    def provision_single_member(value, adapter)
      return value if value.blank?

      membership = WorkspaceMemberProvisioner.find_or_provision!(
        workspace: @workspace, platform_user_id: value, adapter: adapter
      )
      membership&.id
    end

    def provision_multiple_members(value, adapter)
      return value unless value.is_a?(Array)

      value.filter_map do |slack_id|
        membership = WorkspaceMemberProvisioner.find_or_provision!(
          workspace: @workspace, platform_user_id: slack_id, adapter: adapter
        )
        membership&.id
      end
    end
  end
end
