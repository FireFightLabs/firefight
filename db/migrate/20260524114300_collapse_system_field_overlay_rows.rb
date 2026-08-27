class CollapseSystemFieldOverlayRows < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # After flipping the resolver to use code defaults + DB overlay, the
  # IncidentFormField rows seeded by previous workspace setups are no-op
  # overlays restating the default. Delete the ones that match defaults
  # exactly. Preserve any that represent real customizations (different
  # required_mode, hidden visibility, or conditions attached).
  def up
    IncidentFormField
      .where(field_source_kind: IncidentFormField::FIELD_SOURCE_KIND_SYSTEM)
      .includes(:incident_form, :incident_conditions)
      .find_each do |row|
      next if row.incident_conditions.any?
      next unless row.visibility_mode == IncidentFormField::VISIBILITY_MODE_VISIBLE

      defn = IncidentSystemField.fetch(row.system_field_key)
      default_required = defn.required_mode_for(row.incident_form.lifecycle_event)

      # Skip rows that override a default that no longer applies (defn now
      # has no entry for this form_slug). Keep them as customizations.
      next if default_required.nil?

      # Delete iff this row matches the default exactly.
      row.destroy if row.required_mode == default_required
    rescue KeyError
      # Unknown system_field_key, leave the row alone, somebody can clean
      # it up separately.
      next
    end
  end

  def down
    # No-op: we can't reconstruct the original rows without losing
    # information, and the resolver will fall back to defaults anyway.
  end
end
