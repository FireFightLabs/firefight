module CatalogEntry::ReferenceManagement
  extend ActiveSupport::Concern

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

  def resolve_reference_target!(attr_def, target_id)
    reference_type_id = attr_def.config["reference_type_id"]
    target = CatalogEntry.where(
      id: target_id,
      catalog_type_id: reference_type_id,
      workspace_id: workspace_id,
      deleted_at: nil
    ).first

    unless target
      raise ActiveRecord::RecordInvalid.new(self),
        "Referenced entry not found for '#{attr_def.name}'"
    end

    target
  end

  def upsert_reference!(attr_def, target_entry)
    rel = outgoing_relationships.find_or_initialize_by(
      catalog_attribute_definition: attr_def,
      relationship_key: attr_def.slug
    )
    rel.assign_attributes(
      target_entry: target_entry,
      workspace: workspace
    )
    rel.save!
  end
end
