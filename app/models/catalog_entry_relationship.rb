# One reference attribute's value on one entry. The attribute definition is
# the relationship's identity: which attribute it fills, and therefore what
# key it renders under. The unique index on (source, definition) is what
# keeps a single-valued reference single.
class CatalogEntryRelationship < ApplicationRecord
  belongs_to :workspace
  belongs_to :source_entry, class_name: "CatalogEntry"
  belongs_to :target_entry, class_name: "CatalogEntry"
  belongs_to :catalog_attribute_definition

  validate :same_workspace
  validate :no_self_reference

  delegate :slug, to: :catalog_attribute_definition, prefix: :attribute

  private

  def same_workspace
    return unless source_entry && target_entry

    if source_entry.workspace_id != target_entry.workspace_id
      errors.add(:base, "source and target entries must belong to the same workspace")
    end
  end

  def no_self_reference
    return unless source_entry_id && target_entry_id

    if source_entry_id == target_entry_id
      errors.add(:base, "an entry cannot reference itself")
    end
  end
end
