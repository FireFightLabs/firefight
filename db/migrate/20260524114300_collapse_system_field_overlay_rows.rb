class CollapseSystemFieldOverlayRows < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Seeded overlay rows that restate the code default are deleted. Real customizations are kept.
  def up
    IncidentFormField
      .where(field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM)
      .includes(:incident_form, :incident_conditions)
      .find_each do |row|
      next if row.incident_conditions.any?
      next unless row.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE

      defn = IncidentSystemField.fetch(row.system_field_key)
      default_required = defn.required_mode_for(row.incident_form.lifecycle_event)

      # A default that no longer applies, kept as a customization.
      next if default_required.nil?

      row.destroy if row.required_mode == default_required
    rescue KeyError
      # Unknown system_field_key, left alone.
      next
    end
  end

  def down
    # The original rows cannot be reconstructed, and the resolver falls back to defaults.
  end
end
