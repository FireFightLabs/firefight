module CatalogType::SoftDeletion
  extend ActiveSupport::Concern

  def soft_delete!
    raise ActiveRecord::RecordNotDestroyed, "System types cannot be deleted" if system?

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
