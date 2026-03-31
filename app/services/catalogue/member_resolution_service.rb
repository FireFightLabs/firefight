module Catalogue
  class MemberResolutionService
    def initialize(workspace)
      @workspace = workspace
    end

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

    def resolve_for_entries(entries, type)
      member_defs = type.catalog_attribute_definitions.select do |d|
        d.attribute_type.in?([ CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER,
                               CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS ])
      end
      return [] if member_defs.empty?

      member_keys = member_defs.map(&:key)
      member_ids = entries.flat_map do |entry|
        attrs = entry.entry_attributes
        member_keys.flat_map { |k| Array(attrs[k]) }
      end.compact.uniq

      return [] if member_ids.empty?

      @workspace.workspace_memberships.where(id: member_ids)
        .includes(:user)
        .map { |m| { id: m.id, name: m.display_name, avatarUrl: m.user.avatar_url } }
    end

    private

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
