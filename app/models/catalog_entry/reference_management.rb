module CatalogEntry::ReferenceManagement
  extend ActiveSupport::Concern

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def sync_references!(reference_attrs)
    definitions = catalog_type.catalog_attribute_definitions.reference_type.index_by(&:slug)

    reference_attrs.each do |key, value|
      attr_def = definitions[key.to_s]
      next unless attr_def

      if value.blank?
        outgoing_relationships.where(catalog_attribute_definition: attr_def).delete_all
      else
        target_entry = resolve_reference_target!(attr_def, value)
        upsert_reference!(attr_def, target_entry)
      end
    end
  end

  def soft_delete!
    transaction do
      CatalogEntryRelationship.where(source_entry_id: id).delete_all
      CatalogEntryRelationship.where(target_entry_id: id).delete_all
      update!(deleted_at: Time.current)
    end
  end

  private

  # The dashboard holds entry ids, an agent holds slugs. The id lookup is
  # guarded because a slug reaching a uuid column raises out of the driver
  # before the missing-entry message below can be reported.
  def resolve_reference_target!(attr_def, target_reference)
    reference = target_reference.to_s
    scope = CatalogEntry.where(
      catalog_type_id: attr_def.config["reference_type_id"],
      workspace_id: workspace_id,
      deleted_at: nil
    )
    target = reference.match?(UUID_FORMAT) ? scope.find_by(id: reference) : scope.find_by(slug: reference)

    unless target
      raise ActiveRecord::RecordInvalid.new(self),
        "Referenced entry #{reference.inspect} not found for '#{attr_def.name}'"
    end

    target
  end

  def upsert_reference!(attr_def, target_entry)
    rel = outgoing_relationships.find_or_initialize_by(catalog_attribute_definition: attr_def)
    rel.assign_attributes(
      target_entry: target_entry,
      workspace: workspace
    )
    rel.save!
  end
end
