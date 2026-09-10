class CollapseDefaultIncidentFormsAndLeadRole < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Seeded rows that restate the code default are deleted. Renamed, repositioned or
  # referenced ones are kept.
  def up
    IncidentForm.find_each do |form|
      defaults = IncidentForm.defaults_for(form.slug)
      next unless defaults
      next if form.incident_form_fields.any? # has customizations attached
      next if form.name != defaults[:name]
      next if form.description != defaults[:description]
      next if form.lifecycle_event != defaults[:lifecycle_event]
      next if form.position != defaults[:position]

      form.destroy
    end

    IncidentRole.where(slug: IncidentRole::SLUG_INCIDENT_LEAD).find_each do |role|
      defaults = IncidentRole.defaults_for(role.slug)
      next unless defaults
      next if role.incident_role_assignments.any? # has assignments attached
      next if role.deleted_at.present?
      next if role.name != defaults[:name]
      next if role.description != defaults[:description]
      next if role.position != defaults[:position]

      role.destroy
    end
  end

  def down
  end
end
