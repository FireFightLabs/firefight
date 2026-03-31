class CatalogEntry < ApplicationRecord
  # The "attributes" column shadows ActiveRecord's #attributes method.
  # Override the safety check so Rails does not raise DangerousAttributeError.
  # Access the column via self[:attributes] or entry_attributes instead.
  def self.instance_method_already_implemented?(method_name)
    return false if method_name.to_s.start_with?("attributes")
    super
  end

  include CatalogEntry::AttributeValidation
  include CatalogEntry::ReferenceManagement

  belongs_to :workspace
  belongs_to :catalog_type

  has_many :outgoing_relationships, class_name: "CatalogEntryRelationship", foreign_key: :source_entry_id
  has_many :incoming_relationships, class_name: "CatalogEntryRelationship", foreign_key: :target_entry_id

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :catalog_type_id }

  validate :workspace_matches_type

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:name) }
  scope :with_relationships, -> { includes(outgoing_relationships: [ :target_entry, :catalog_attribute_definition ]) }

  def entry_attributes
    self[:attributes] || {}
  end

  private

  def workspace_matches_type
    return unless catalog_type

    if workspace_id != catalog_type.workspace_id
      errors.add(:workspace, "must match the catalog type's workspace")
    end
  end
end
