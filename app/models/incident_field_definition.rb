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

  MULTI_VALUED_TYPES = [ TYPE_MULTI_SELECT, TYPE_CATALOG_MULTI_REFERENCE ].freeze
  SELECTABLE_TYPES = [
    TYPE_SINGLE_SELECT,
    TYPE_MULTI_SELECT,
    TYPE_CATALOG_REFERENCE,
    TYPE_CATALOG_MULTI_REFERENCE
  ].freeze

  # Validation and the field dialog both read this, so the rule and the
  # picker cannot drift.
  OPTION_SOURCES_BY_FIELD_TYPE = {
    TYPE_TEXT => [ OPTION_SOURCE_NONE ],
    TYPE_NUMBER => [ OPTION_SOURCE_NONE ],
    TYPE_LINK => [ OPTION_SOURCE_NONE ],
    TYPE_SINGLE_SELECT => [ OPTION_SOURCE_FIXED, OPTION_SOURCE_CATALOG ],
    TYPE_MULTI_SELECT => [ OPTION_SOURCE_FIXED, OPTION_SOURCE_CATALOG ],
    TYPE_CATALOG_REFERENCE => [ OPTION_SOURCE_CATALOG ],
    TYPE_CATALOG_MULTI_REFERENCE => [ OPTION_SOURCE_CATALOG ]
  }.freeze

  # A stored value is one of three things whatever the field type. Everything
  # reading or writing a value dispatches on this.
  STORAGE_OPTION = :option
  STORAGE_CATALOG_ENTRY = :catalog_entry
  STORAGE_SCALAR = :scalar

  # Slack caps a select at 100 options and fails the whole views.open beyond that.
  MAX_OPTIONS = 100

  belongs_to :workspace
  belongs_to :catalog_type, optional: true

  has_many :incident_form_fields, dependent: :restrict_with_error
  # Ordered here so includes preloads in display order. Calling .ordered
  # downstream would discard the preload.
  has_many :incident_field_options, -> { ordered }, dependent: :destroy, inverse_of: :incident_field_definition
  has_many :incident_field_values, dependent: :restrict_with_error

  validates :slug, presence: true,
    uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } }
  validates :name, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :option_source, presence: true, inclusion: { in: OPTION_SOURCES }
  validates :position, presence: true

  validate :slug_immutable, on: :update
  validate :shape_immutable_once_in_use, on: :update
  validate :options_match_field_type
  validate :option_count_within_platform_limit

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :created_at) }

  def self.usage_association
    :incident_form_fields
  end

  # Attaches usage and value counts for the whole list in a fixed number of queries.
  def self.for_settings(relation)
    definitions = relation
      .ordered
      .with_usage_counts
      .includes(:incident_field_options, :catalog_type)
      .to_a

    IncidentFieldOption.preload_usage_counts(definitions)

    value_counts = IncidentFieldValue
      .where(incident_field_definition_id: definitions.map(&:id))
      .group(:incident_field_definition_id)
      .count
    definitions.each { |definition| definition.value_count = value_counts.fetch(definition.id, 0) }

    definitions
  end

  def self.generate_slug(name)
    Sluggable.word_slug(name)
  end

  def multi_valued?
    self.class.multi_valued?(field_type)
  end

  def self.multi_valued?(field_type)
    MULTI_VALUED_TYPES.include?(field_type)
  end

  def selectable?
    self.class.selectable?(field_type)
  end

  def self.selectable?(field_type)
    SELECTABLE_TYPES.include?(field_type)
  end

  def storage_kind
    return STORAGE_SCALAR unless selectable?

    catalog_options? ? STORAGE_CATALOG_ENTRY : STORAGE_OPTION
  end

  # The column a submitted entry lands in.
  def value_attributes_for(entry)
    case storage_kind
    when STORAGE_OPTION        then { incident_field_option_id: entry }
    when STORAGE_CATALOG_ENTRY then { catalog_entry_id: entry }
    when STORAGE_SCALAR
      field_type == TYPE_NUMBER ? { value_number: entry } : { value_text: entry.to_s }
    end
  end

  # Disabled and archived rows drop out without disturbing the incidents
  # holding them. Filters in Ruby so a preloaded association survives.
  def selectable_values
    case storage_kind
    when STORAGE_OPTION
      incident_field_options.select(&:enabled?).to_h { |option| [ option.id, option.label ] }
    when STORAGE_CATALOG_ENTRY
      return {} if catalog_type_id.blank?

      workspace.catalog_entries.active
        .where(catalog_type_id: catalog_type_id)
        .order(:name)
        .to_h { |entry| [ entry.id, entry.name ] }
    else
      {}
    end
  end

  def value_count
    @value_count ||= incident_field_values.count
  end

  attr_writer :value_count

  # Values on incidents are history and the association refuses to cascade
  # them, so this says no before the screen offers to.
  def deletion_blocked_reason
    return super if super
    return if value_count.zero?

    "#{name} holds a value on #{value_count} #{'incident'.pluralize(value_count)} and cannot be deleted. " \
      "Disable it instead, which keeps the history and stops it being collected again."
  end

  # Changing the type or source once incidents hold values silently
  # reinterprets history.
  def shape_change_blocked_reason
    return if value_count.zero?

    "#{name} is in use by #{value_count} #{'incident'.pluralize(value_count)}, " \
      "so its field type and option source cannot be changed. Disable it and add a new field instead."
  end

  # Rows with an id update in place, so a rename never changes what incidents point at.
  def sync_options!(options_params)
    incoming = Array(options_params)

    transaction do
      remove_options_absent_from!(incoming)

      incoming.each_with_index do |params, index|
        attributes = {
          label: params[:label].to_s.strip,
          position: index,
          disabled_at: option_disabled_at(params)
        }

        if params[:id].present?
          incident_field_options.find(params[:id]).update!(attributes)
        else
          incident_field_options.create!(attributes)
        end
      end

      incident_field_options.reset
      raise ActiveRecord::RecordInvalid, self unless valid?
    end
  end

  def fixed_options?
    option_source == OPTION_SOURCE_FIXED
  end

  def catalog_options?
    option_source == OPTION_SOURCE_CATALOG
  end

  private

  def slug_immutable
    return unless slug_changed?

    errors.add(:slug, "cannot be changed after creation")
  end

  def shape_immutable_once_in_use
    return unless field_type_changed? || option_source_changed?

    reason = shape_change_blocked_reason
    errors.add(:base, reason) if reason
  end

  def option_count_within_platform_limit
    return unless fixed_options?

    enabled = incident_field_options.reject(&:marked_for_destruction?).count(&:enabled?)
    return if enabled <= MAX_OPTIONS

    errors.add(:base, "cannot have more than #{MAX_OPTIONS} enabled options")
  end

  def option_disabled_at(params)
    return nil unless ActiveModel::Type::Boolean.new.cast(params[:disabled])

    existing = params[:id].present? ? incident_field_options.find_by(id: params[:id]) : nil
    existing&.disabled_at || Time.current
  end

  # The foreign key raises InvalidForeignKey with nothing a user can read,
  # so the blocked reason is checked first.
  def remove_options_absent_from!(incoming)
    keep_ids = incoming.filter_map { |params| params[:id].presence }
    removed = incident_field_options.where.not(id: keep_ids).to_a
    return if removed.empty?

    counts = IncidentFieldOption.usage_counts_for(self)
    removed.each { |option| option.usage_count = counts.fetch(option.id, 0) }

    blocked = removed.filter_map(&:deletion_blocked_reason)
    if blocked.any?
      errors.add(:base, blocked.first)
      raise ActiveRecord::RecordInvalid, self
    end

    removed.each(&:destroy!)
  end

  def options_match_field_type
    allowed = OPTION_SOURCES_BY_FIELD_TYPE.fetch(field_type) { return }
    unless allowed.include?(option_source)
      errors.add(:option_source, "must be #{allowed.join(' or ')} for #{field_type} fields")
      return
    end

    case option_source
    when OPTION_SOURCE_FIXED
      if incident_field_options.reject(&:marked_for_destruction?).none?(&:enabled?)
        errors.add(:base, "must include at least one enabled option for fixed select fields")
      end
    when OPTION_SOURCE_CATALOG
      validate_catalog_type_scope!
    end
  end

  def validate_catalog_type_scope!
    if catalog_type_id.blank?
      errors.add(:catalog_type, "must be selected")
      return
    end

    unless workspace.catalog_types.active.exists?(id: catalog_type_id)
      errors.add(:catalog_type, "must be an active catalog type in the workspace")
    end
  end
end
