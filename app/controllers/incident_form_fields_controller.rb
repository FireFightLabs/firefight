class IncidentFormFieldsController < InertiaController
  authorizes Ability::Action::RESOURCE_FORMS, create: :create, update: %i[update move_up move_down reorder], delete: :destroy
  before_action :set_form_field, only: [ :update, :destroy, :move_up, :move_down ]

  # set_form_field runs before any action, so a bad synthetic id cannot be
  # rescued inline the way the other failures are.
  rescue_from ArgumentError do |error|
    redirect_to settings_forms_path, alert: error.message
  end

  def create
    form = resolve_form(params[:incident_form_id])
    field_definition = current_workspace.incident_field_definitions.active.find(params[:incident_field_definition_id])
    form_service.add_custom_field(form, field_definition)
    redirect_to settings_forms_path(form: form.id), notice: "#{field_definition.name} was added to the #{form.name} form."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_forms_path(form: form&.id),
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    form_service.update_field(
      @form_field,
      visibility_mode: params.require(:visibility_mode),
      required_mode: params.require(:required_mode)
    )

    if params.key?(:conditions)
      conditions = parse_conditions(params[:conditions])
      @form_field.sync_conditions!(conditions)
    end

    redirect_to settings_forms_path(form: @form_field.incident_form_id), notice: "#{@form_field.source_name} was updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_forms_path(form: @form_field.incident_form_id),
      inertia: { errors: e.record.errors.to_hash }
  end

  def destroy
    form_id = @form_field.incident_form_id
    name = @form_field.source_name
    form_service.remove_field(@form_field)
    redirect_to settings_forms_path(form: form_id), notice: "#{name} was removed from the form."
  end

  def move_up
    form_id = @form_field.incident_form_id
    form_service.move_up(@form_field)
    redirect_to settings_forms_path(form: form_id)
  end

  def move_down
    form_id = @form_field.incident_form_id
    form_service.move_down(@form_field)
    redirect_to settings_forms_path(form: form_id)
  end

  def reorder
    form = resolve_form(params.require(:incident_form_id))
    ordered_ids = params.require(:ordered_ids)
    form_service.reorder(form, ordered_ids)
    redirect_to settings_forms_path(form: form.id), notice: "Field order updated."
  end

  private

  # Accepts either a persisted form's DB id or a `default:<slug>` synthetic
  # id from the settings editor. Synthetic ids materialize the default into
  # a real DB row on first use via `Workspace#ensure_incident_form!`.
  def resolve_form(id_or_default)
    id = id_or_default.to_s
    if id.start_with?(IncidentFormField::SYNTHETIC_PREFIX)
      current_workspace.ensure_incident_form!(id.delete_prefix(IncidentFormField::SYNTHETIC_PREFIX))
    else
      current_workspace.incident_forms.find(id)
    end
  end

  # Accepts a persisted overlay row's id, or a `default:<system_field_key>`
  # synthetic id for a system field this workspace has never customized, which
  # is materialized into a real row on first edit.
  def set_form_field
    id = params[:id].to_s

    @form_field = if id.start_with?(IncidentFormField::SYNTHETIC_PREFIX)
      form_service.ensure_system_field!(
        resolve_form(params.require(:incident_form_id)),
        id.delete_prefix(IncidentFormField::SYNTHETIC_PREFIX)
      )
    else
      IncidentFormField.joins(:incident_form)
        .where(incident_forms: { workspace_id: current_workspace.id })
        .find(id)
    end
  end

  def form_service
    @form_service ||= IncidentFormService.new(current_workspace)
  end

  def parse_conditions(raw)
    return [] if raw.blank?

    Array(raw).map do |c|
      {
        condition_field: c[:condition_field],
        operator: c[:operator],
        values: Array(c[:values]),
        incident_field_definition_id: c[:incident_field_definition_id].presence
      }
    end
  end
end
