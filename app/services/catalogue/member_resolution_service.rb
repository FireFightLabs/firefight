module Catalogue
  class MemberResolutionService
    def initialize(workspace)
      @workspace = workspace
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
  end
end
