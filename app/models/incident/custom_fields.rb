# Projects the incident_field_values rows into the flat `key => value` hash
# every entry point already speaks. Assignment is deferred to after_save
# because a new incident has no id to hang value rows off yet.
module Incident::CustomFields
  extend ActiveSupport::Concern

  included do
    has_many :incident_field_values, dependent: :destroy

    after_save :persist_pending_custom_fields, if: -> { @pending_custom_fields }
  end

  def custom_fields
    return @pending_custom_fields if @pending_custom_fields

    project(&:reference_or_scalar)
  end

  def custom_fields=(hash)
    @pending_custom_fields = (hash || {}).transform_keys(&:to_s)
  end

  def custom_fields_for_display
    project(&:display_label)
  end

  private

  def project(&block)
    rows = incident_field_values
      .includes(:incident_field_definition, :incident_field_option, :catalog_entry)
      .ordered

    rows.group_by(&:incident_field_definition).each_with_object({}) do |(definition, group), result|
      values = group.map(&block).compact
      next if values.empty?

      result[definition.slug] = definition.multi_valued? ? values : values.first
    end
  end

  def persist_pending_custom_fields
    pending = @pending_custom_fields
    @pending_custom_fields = nil

    definitions = workspace.incident_field_definitions.where(slug: pending.keys).index_by(&:slug)

    transaction do
      incident_field_values.where(incident_field_definition_id: definitions.values.map(&:id)).delete_all

      pending.each do |key, value|
        definition = definitions[key]
        next if definition.nil? || value.blank?

        Array.wrap(value).each_with_index do |entry, index|
          next if entry.blank?

          incident_field_values.create!(
            definition.value_attributes_for(entry).merge(
              incident_field_definition: definition,
              position: index
            )
          )
        end
      end
    end
  end
end
