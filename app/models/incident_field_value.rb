class IncidentFieldValue < ApplicationRecord
  belongs_to :incident
  belongs_to :incident_field_definition
  belongs_to :incident_field_option, optional: true
  belongs_to :catalog_entry, optional: true

  validate :exactly_one_value

  scope :ordered, -> { order(:position, :created_at) }

  def reference_or_scalar
    return incident_field_option_id if incident_field_option_id.present?
    return catalog_entry_id if catalog_entry_id.present?
    return format_number(value_number) if value_number.present?

    value_text
  end

  def display_label
    return incident_field_option.label if incident_field_option_id.present?
    return catalog_entry.name if catalog_entry_id.present?
    return format_number(value_number) if value_number.present?

    value_text
  end

  private

  def format_number(number)
    number.to_s.sub(/\.0+\z/, "").sub(/(\.\d*?)0+\z/, '\1')
  end

  def exactly_one_value
    set = [ incident_field_option_id, catalog_entry_id, value_text, value_number ].count(&:present?)
    return if set == 1

    errors.add(:base, "must hold exactly one of an option, a catalog entry, text, or a number")
  end
end
