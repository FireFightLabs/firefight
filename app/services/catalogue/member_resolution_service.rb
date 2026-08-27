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

    # One row per person for the member pickers. Anyone already here is offered
    # under their membership id, which is what an entry stores and what a read
    # hands back, so the same person cannot appear twice under two identifiers.
    # Everyone else is offered under their platform id and becomes a member the
    # moment they are picked.
    #
    # A member the platform has deactivated is dropped. One the platform simply
    # did not return is kept, because an incomplete answer is not the same as a
    # person who has left, and they may still hold entries.
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
