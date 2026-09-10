# A field naming a system type gains one relationship hop keyed by system_key and its
# scalar attributes as "<field>.<attribute>". Input fields are never overwritten.
class Policy::ContextBuilder
  def self.build(workspace:, fields:)
    context = Policy.normalize_context(fields)

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
    workspace.catalog_entries.in_system_type(system_key).find_by(slug: slug)
  end

  def self.merge_related_entries(context, entry)
    entry.active_outgoing_relationships.each do |relationship|
      target = relationship.target_entry
      target_key = target.catalog_type.system_key
      next if target_key.blank? || context[target_key].present?

      context[target_key] = target.slug
    end
  end

  def self.merge_entry_attributes(context, system_key, entry)
    entry.entry_attributes.each do |name, value|
      next unless value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false

      key = "#{system_key}.#{name}"
      context[key] = value.to_s unless context.key?(key)
    end
  end
end
