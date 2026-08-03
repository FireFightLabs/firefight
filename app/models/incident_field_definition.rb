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

  # Slack caps a select at 100 options and fails the whole views.open beyond
  # that, taking the entire form down rather than just this field.
  MAX_OPTIONS = 100

  belongs_to :workspace
  belongs_to :catalog_type, optional: true

  has_many :incident_form_fields, dependent: :restrict_with_error
  # Ordered on the association so `includes` preloads in display order. Calling
  # .ordered downstream would build a fresh relation and discard the preload.
  has_many :incident_field_options, -> { ordered }, dependent: :destroy, inverse_of: :incident_field_definition
  has_many :incident_field_values, dependent: :restrict_with_error

  validates :key, presence: true,
    uniqueness: { scope: :workspace_id, conditions: -> { where(deleted_at: nil) } }
  validates :name, presence: true
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :option_source, presence: true, inclusion: { in: OPTION_SOURCES }
  validates :position, presence: true

  validate :key_immutable, on: :update
  validate :shape_immutable_once_in_use, on: :update
  validate :options_match_field_type
  validate :option_count_within_platform_limit

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position, :created_at) }

  def self.usage_association
    :incident_form_fields
  end

  # The only supported way to hand definitions to a settings serializer.
  # Attaches option usage counts and value counts for the whole list in a fixed
  # number of queries rather than per row.
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

  def self.generate_key(name)
    name.to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end

  def multi_valued?
    MULTI_VALUED_TYPES.include?(field_type)
  end

  def value_count
    @value_count ||= incident_field_values.count
  end

  attr_writer :value_count

  # field_type and option_source decide how stored values are interpreted, so
  # changing them once incidents hold values silently reinterprets history.
  def shape_change_blocked_reason
    return if value_count.zero?

    "#{name} is in use by #{value_count} #{'incident'.pluralize(value_count)}, " \
      "so its field type and option source cannot be changed. Disable it and add a new field instead."
  end

  # Rows carrying an id are updated in place, so a rename never changes what
  # incidents point at.
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

  def key_immutable
    return unless key_changed?

    errors.add(:key, "cannot be changed after creation")
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

  # The foreign key is the real stop, but it raises InvalidForeignKey with no
  # sentence a user can read, so the blocked reason is checked first.
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
    case field_type
    when TYPE_TEXT, TYPE_NUMBER, TYPE_LINK
      validate_none_option_source!
    when TYPE_SINGLE_SELECT, TYPE_MULTI_SELECT
      validate_select_field_options!
    when TYPE_CATALOG_REFERENCE, TYPE_CATALOG_MULTI_REFERENCE
      validate_catalog_reference_options!
    end
  end

  def validate_none_option_source!
    if option_source != OPTION_SOURCE_NONE
      errors.add(:option_source, "must be none for #{field_type} fields")
    end
  end

  def validate_select_field_options!
    if option_source == OPTION_SOURCE_FIXED
      if incident_field_options.reject(&:marked_for_destruction?).none?(&:enabled?)
        errors.add(:base, "must include at least one enabled option for fixed select fields")
      end
    elsif option_source == OPTION_SOURCE_CATALOG
      validate_catalog_type_scope!
    else
      errors.add(:option_source, "must be fixed or catalog for #{field_type} fields")
    end
  end

  def validate_catalog_reference_options!
    if option_source != OPTION_SOURCE_CATALOG
      errors.add(:option_source, "must be catalog for #{field_type} fields")
      return
    end

    validate_catalog_type_scope!
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
