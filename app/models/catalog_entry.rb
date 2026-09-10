class CatalogEntry < ApplicationRecord
  # The attributes column shadows ActiveRecord#attributes. Read it through
  # self[:attributes] or entry_attributes.
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
  validates :slug, presence: true, uniqueness: { scope: :catalog_type_id, conditions: -> { where(deleted_at: nil) } }
  validate :source_and_external_id_paired

  validate :workspace_matches_type
  validate :slug_immutable, on: :update

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:name) }
  scope :with_relationships, -> { includes(outgoing_relationships: [ :target_entry, :catalog_attribute_definition ]) }
  scope :search, ->(query) { where("catalog_entries.name ILIKE ?", "%#{sanitize_sql_like(query)}%") }
  scope :externally_managed, -> { where.not(source: nil) }

  scope :in_system_type, ->(system_keys) { active.joins(:catalog_type).where(catalog_types: { system_key: system_keys }) }

  def entry_attributes
    self[:attributes] || {}
  end

  def role_value(role)
    slug = catalog_type.role_attribute(role)&.slug
    slug && entry_attributes[slug]
  end

  # Filters in memory when the association is loaded, preloads otherwise.
  def active_outgoing_relationships
    relationships = outgoing_relationships
    relationships = relationships.includes(target_entry: :catalog_type) unless relationships.loaded?
    relationships.select { |relationship| relationship.target_entry.deleted_at.nil? }
  end

  private

  def workspace_matches_type
    return unless catalog_type

    if workspace_id != catalog_type.workspace_id
      errors.add(:workspace, "must match the catalog type's workspace")
    end
  end

  def slug_immutable
    if slug_changed?
      errors.add(:slug, "cannot be changed after creation")
    end
  end

  def source_and_external_id_paired
    if source.present? && external_id.blank?
      errors.add(:external_id, "is required when source is set")
    elsif external_id.present? && source.blank?
      errors.add(:source, "is required when external_id is set")
    end
  end
end
