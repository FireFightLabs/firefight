# Enriches a raw field hash with catalog-resolved context before policy
# evaluation. For each field naming a catalog system type (service, team,
# environment, functionality) it resolves the entry by slug and merges:
#   - one relationship hop: related entries keyed by their type's system_key
#     (e.g. service "auth_service" --owner_team--> team "platform_team"
#      adds "team" => "platform_team")
#   - the entry's scalar attributes as "<field>.<attribute>"
#     (e.g. "service.tier" => "Critical")
# Explicit input fields are never overwritten.
class PolicyContextBuilder
  def self.build(workspace:, fields:)
    context = PolicyRouter.normalize_context(fields)

    CatalogType::SYSTEM_KEYS.each do |system_key|
      slug = context[system_key]
      next if slug.blank?

      entry = resolve_entry(workspace, system_key, slug)
      next unless entry

      merge_related_entries(context, entry)
      merge_entry_attributes(context, system_key, entry)
    end

    context
  end

  def self.resolve_entry(workspace, system_key, slug)
    CatalogEntry.active
      .joins(:catalog_type)
      .where(workspace: workspace, slug: slug)
      .find_by(catalog_types: { system_key: system_key })
  end

  def self.merge_related_entries(context, entry)
    entry.outgoing_relationships.includes(target_entry: :catalog_type).each do |relationship|
      target = relationship.target_entry
      next if target.deleted_at?

      target_key = target.catalog_type.system_key
      next if target_key.blank? || context[target_key].present?

      context[target_key] = target.slug
    end
  end

  def self.merge_entry_attributes(context, system_key, entry)
    entry[:attributes].each do |name, value|
      next unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

      key = "#{system_key}.#{name}"
      context[key] = value.to_s unless context.key?(key)
    end
  end
end
