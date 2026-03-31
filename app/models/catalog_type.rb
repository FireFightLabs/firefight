class CatalogType < ApplicationRecord
  include CatalogType::AttributeDefinitionManagement
  include CatalogType::SoftDeletion

  KIND_SYSTEM = "system"
  KIND_CUSTOM = "custom"
  KINDS = [ KIND_SYSTEM, KIND_CUSTOM ].freeze

  SYSTEM_KEY_SERVICE = "service"
  SYSTEM_KEY_TEAM = "team"
  SYSTEM_KEY_ENVIRONMENT = "environment"
  SYSTEM_KEY_FUNCTIONALITY = "functionality"
  SYSTEM_KEYS = [ SYSTEM_KEY_SERVICE, SYSTEM_KEY_TEAM, SYSTEM_KEY_ENVIRONMENT, SYSTEM_KEY_FUNCTIONALITY ].freeze
  RESERVED_SLUGS = SYSTEM_KEYS

  belongs_to :workspace
  has_many :catalog_attribute_definitions
  has_many :catalog_entries

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :position, presence: true
  validates :system_key, inclusion: { in: SYSTEM_KEYS, allow_nil: true },
    uniqueness: { scope: :workspace_id, allow_nil: true }

  validate :system_key_presence_matches_kind
  validate :custom_type_cannot_use_reserved_slugs
  validate :system_fields_immutable, on: :update

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }
  scope :system_types, -> { where(kind: KIND_SYSTEM) }
  scope :custom_types, -> { where(kind: KIND_CUSTOM) }

  scope :with_entry_counts, -> {
    left_joins(:catalog_entries)
      .group("catalog_types.id")
      .select("catalog_types.*, COUNT(CASE WHEN catalog_entries.id IS NOT NULL AND catalog_entries.deleted_at IS NULL THEN 1 END) AS entry_count")
  }

  def system? = kind == KIND_SYSTEM
  def custom? = kind == KIND_CUSTOM

  def entry_count
    read_attribute("entry_count") || catalog_entries.where(deleted_at: nil).count
  end

  def reference_entry_options
    reference_type_ids = catalog_attribute_definitions
      .select { |d| d.attribute_type == CatalogAttributeDefinition::TYPE_REFERENCE }
      .filter_map { |d| d.config["reference_type_id"] }

    return [] if reference_type_ids.empty?

    workspace.catalog_entries.active
      .where(catalog_type_id: reference_type_ids)
      .pluck(:id, :name, :catalog_type_id)
      .map { |id, name, type_id| { id: id, name: name, typeId: type_id } }
  end

  private

  def system_key_presence_matches_kind
    if system? && system_key.blank?
      errors.add(:system_key, "must be present for system types")
    elsif custom? && system_key.present?
      errors.add(:system_key, "must be blank for custom types")
    end
  end

  def custom_type_cannot_use_reserved_slugs
    return unless custom?

    if RESERVED_SLUGS.include?(slug)
      errors.add(:slug, "is reserved for system types")
    end
  end

  def system_fields_immutable
    return unless system?

    if slug_changed?
      errors.add(:slug, "cannot be changed for system types")
    end

    if system_key_changed?
      errors.add(:system_key, "cannot be changed for system types")
    end
  end
end
