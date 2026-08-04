class IncidentFormField < ApplicationRecord
  FIELD_SOURCE_KIND_SYSTEM = "system"
  FIELD_SOURCE_KIND_CUSTOM = "custom"
  FIELD_SOURCE_KINDS = [ FIELD_SOURCE_KIND_SYSTEM, FIELD_SOURCE_KIND_CUSTOM ].freeze

  VISIBILITY_MODE_VISIBLE = "visible"
  VISIBILITY_MODE_HIDDEN = "hidden"
  VISIBILITY_MODES = [ VISIBILITY_MODE_VISIBLE, VISIBILITY_MODE_HIDDEN ].freeze

  # Registry value meaning "belongs on this form, but off until enabled".
  REQUIRED_MODE_AVAILABLE = "available"

  REQUIRED_MODE_OPTIONAL = "optional"
  REQUIRED_MODE_REQUIRED = "required"
  REQUIRED_MODE_FIXED_REQUIRED = "fixed_required"
  REQUIRED_MODES = [ REQUIRED_MODE_OPTIONAL, REQUIRED_MODE_REQUIRED, REQUIRED_MODE_FIXED_REQUIRED ].freeze

  belongs_to :incident_form
  belongs_to :incident_field_definition, optional: true
  has_many :incident_conditions, as: :conditionable, dependent: :destroy

  validates :field_source_kind, presence: true, inclusion: { in: FIELD_SOURCE_KINDS }
  validates :position, presence: true
  validates :visibility_mode, presence: true, inclusion: { in: VISIBILITY_MODES }
  validates :required_mode, presence: true, inclusion: { in: REQUIRED_MODES }

  validate :exactly_one_field_source
  validate :system_field_key_valid

  scope :ordered, -> { order(:position, :created_at) }

  def system?
    field_source_kind == FIELD_SOURCE_KIND_SYSTEM
  end

  def custom?
    field_source_kind == FIELD_SOURCE_KIND_CUSTOM
  end

  # A field the incident cannot be written without. Hiding one produces a form
  # that always fails to submit, so visibility is locked wherever required is.
  # incidents.incident_status_id and incident_severity_id are both NOT NULL.
  def locked_visible?
    locked_required?
  end

  def locked_required?
    required_mode == REQUIRED_MODE_FIXED_REQUIRED
  end

  def source_name
    system? ? IncidentSystemField.fetch(system_field_key).name : incident_field_definition&.name
  end

  def sync_conditions!(conditions_params)
    transaction do
      incident_conditions.destroy_all
      conditions_params.each do |cp|
        incident_conditions.create!(
          workspace: incident_form.workspace,
          condition_field: cp[:condition_field],
          operator: cp[:operator],
          values: cp[:values]
        )
      end
    end
  end

  private

  def exactly_one_field_source
    if system?
      if system_field_key.blank? || incident_field_definition_id.present?
        errors.add(:base, "system fields must provide only system_field_key")
      end
    elsif custom?
      if incident_field_definition_id.blank? || system_field_key.present?
        errors.add(:base, "custom fields must provide only incident_field_definition_id")
      end
    end
  end

  def system_field_key_valid
    return unless system?
    return if IncidentSystemField.valid_key?(system_field_key)

    errors.add(:system_field_key, "is not a valid system field")
  end
end
