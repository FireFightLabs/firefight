class CatalogEntryRelationship < ApplicationRecord
  KEY_DEPENDS_ON = "depends_on"
  KEY_DEPLOYED_TO = "deployed_to"
  KEY_RUNS_IN = "runs_in"
  KEY_SUPPORTS = "supports"
  RESERVED_KEYS = [ KEY_DEPENDS_ON, KEY_DEPLOYED_TO, KEY_RUNS_IN, KEY_SUPPORTS ].freeze

  belongs_to :workspace
  belongs_to :source_entry, class_name: "CatalogEntry"
  belongs_to :target_entry, class_name: "CatalogEntry"
  belongs_to :catalog_attribute_definition, optional: true

  validates :relationship_key, presence: true
  validates :source_entry_id, uniqueness: {
    scope: [ :target_entry_id, :relationship_key ],
    message: "already has this relationship"
  }

  validate :same_workspace
  validate :no_self_reference

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
