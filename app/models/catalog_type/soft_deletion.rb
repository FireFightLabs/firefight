module CatalogType::SoftDeletion
  extend ActiveSupport::Concern

  # The rule the controller enforces and the serializer ships. A type that
  # another type's attribute points at cannot go: its entries would vanish
  # from that attribute's picker with no way to retarget it.
  def deletion_blocked_reason
    return "#{name} is a built-in type and cannot be deleted." if system?

    referencing = CatalogAttributeDefinition
      .joins(:catalog_type)
      .where(catalog_types: { workspace_id: workspace_id, deleted_at: nil })
      .where.not(catalog_type_id: id)
      .where("config->>'reference_type_id' = ?", id.to_s)
      .includes(:catalog_type)
      .first
    return nil unless referencing

    "#{name} is referenced by the #{referencing.name} attribute on #{referencing.catalog_type.name}. Remove that attribute before deleting the type."
  end

  def soft_delete!
    blocked_reason = deletion_blocked_reason
    raise ActiveRecord::RecordNotDestroyed, blocked_reason if blocked_reason

    transaction do
      entry_ids = catalog_entries.pluck(:id)

      if entry_ids.any?
        CatalogEntryRelationship.where(source_entry_id: entry_ids).or(
          CatalogEntryRelationship.where(target_entry_id: entry_ids)
        ).delete_all

        catalog_entries.update_all(deleted_at: Time.current)
      end

      update!(deleted_at: Time.current)
    end
  end
end
