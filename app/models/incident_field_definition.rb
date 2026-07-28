class IncidentFieldDefinition < ApplicationRecord
  include Positioned
  include OptionGuards
  include NormalizedDescription

  NOUN = "custom field".freeze
  USAGE_NOUN = "form".freeze

  TYPE_TEXT = "text"
  TYPE_NUMBER = "number"
  TYPE_SINGLE_SELECT = "single_select"
  TYPE_MULTI_SELECT = "multi_select"
  TYPE_LINK = "link"
  TYPE_CATALOG_REFERENCE = "catalog_reference"
  TYPE_CATALOG_MULTI_REFERENCE = "catalog_multi_reference"
  FIELD_TYPES = [
    TYPE_TEXT,
    TYPE_NUMBER,
    TYPE_SINGLE_SELECT,
    TYPE_MULTI_SELECT,
    TYPE_LINK,
    TYPE_CATALOG_REFERENCE,
    TYPE_CATALOG_MULTI_REFERENCE
  ].freeze

  OPTION_SOURCE_NONE = "none"
  OPTION_SOURCE_FIXED = "fixed"
  OPTION_SOURCE_CATALOG = "catalog"
  OPTION_SOURCES = [ OPTION_SOURCE_NONE, OPTION_SOURCE_FIXED, OPTION_SOURCE_CATALOG ].freeze

  belongs_to :workspace

  has_many :incident_form_fields, dependent: :restrict_with_error

  validates :key, presence: true,
    uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } }
  validates :name, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :option_source, presence: true, inclusion: { in: OPTION_SOURCES }
  validates :position, presence: true

  validate :key_immutable, on: :update
  validate :config_matches_field_type

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :created_at) }

  def self.usage_association
    :incident_form_fields
  end

  def self.generate_key(name)
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end

  def options
    config["options"] || []
  end

  def catalog_type_id
    config["catalog_type_id"]
  end

  def catalog_type
    return nil if catalog_type_id.blank?

    workspace.catalog_types.active.find_by(id: catalog_type_id)
  end

  def fixed_options?
    option_source == OPTION_SOURCE_FIXED
  end

  def catalog_options?
    option_source == OPTION_SOURCE_CATALOG
  end

  private

  def key_immutable
    return unless key_changed?

    errors.add(:key, "cannot be changed after creation")
  end

  def config_matches_field_type
    case field_type
    when TYPE_TEXT, TYPE_NUMBER, TYPE_LINK
      validate_none_option_source!
    when TYPE_SINGLE_SELECT, TYPE_MULTI_SELECT
      validate_select_field_config!
    when TYPE_CATALOG_REFERENCE, TYPE_CATALOG_MULTI_REFERENCE
      validate_catalog_reference_config!
    end
  end

  def validate_none_option_source!
    if option_source != OPTION_SOURCE_NONE
      errors.add(:option_source, "must be none for #{field_type} fields")
    end
  end

  def validate_select_field_config!
    if option_source == OPTION_SOURCE_FIXED
      if options.blank? || !options.is_a?(Array)
        errors.add(:config, "must include non-empty options for fixed select fields")
      end
    elsif option_source == OPTION_SOURCE_CATALOG
      validate_catalog_type_scope!
    else
      errors.add(:option_source, "must be fixed or catalog for #{field_type} fields")
    end
  end

  def validate_catalog_reference_config!
    if option_source != OPTION_SOURCE_CATALOG
      errors.add(:option_source, "must be catalog for #{field_type} fields")
      return
    end

    validate_catalog_type_scope!
  end

  def validate_catalog_type_scope!
    if catalog_type_id.blank?
      errors.add(:config, "must include catalog_type_id")
      return
    end

    unless workspace.catalog_types.active.exists?(id: catalog_type_id)
      errors.add(:config, "must reference an active catalog type in the workspace")
    end
  end
end
