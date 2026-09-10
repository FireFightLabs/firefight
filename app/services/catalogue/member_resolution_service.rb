module Catalogue
  class MemberResolutionService
    def initialize(workspace)
      @workspace = workspace
    end

    def resolve_for_entries(entries, type)
      member_keys = type.member_attribute_slugs
      return [] if member_keys.empty?

      member_ids = entries.flat_map do |entry|
        attrs = entry.entry_attributes
        member_keys.flat_map { |key| Array(attrs[key]) }
      end.compact.uniq

      return [] if member_ids.empty?

      @workspace.workspace_memberships.where(id: member_ids)
        .includes(:user)
        .map { |membership| member_row(membership) }
    end

    # Members are keyed by membership id and everyone else by platform id, so one person never appears twice.
    # A member the platform did not return is kept, an incomplete answer is not a person who left.
    def pickable_members
      known = @workspace.workspace_memberships.includes(:user).index_by(&:platform_user_id)
      directory = @workspace.adapter.member_directory

      offered = directory[:members].map do |member|
        membership = known.delete(member[:id])
        membership ? member_row(membership) : member
      end

      directory[:deactivated_ids].each { |platform_user_id| known.delete(platform_user_id) }

      offered + known.values.map { |membership| member_row(membership) }
    end

    private

    def member_row(membership)
      { id: membership.id, name: membership.display_name, avatarUrl: membership.user.avatar_url }
    end
  end
end
