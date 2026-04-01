class IncidentFormFieldsController < InertiaController
  before_action :require_authentication
  before_action :set_form_field, only: [ :update, :destroy, :move_up, :move_down ]

  def create
    form = current_workspace.incident_forms.find(params[:incident_form_id])
    field_definition = current_workspace.incident_field_definitions.active.find(params[:incident_field_definition_id])
    form_service.add_custom_field(form, field_definition)
    redirect_to settings_forms_path(form: form.id)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_forms_path(form: form.id),
      inertia: { errors: e.record.errors.to_hash }
  end

  def update
    form_service.update_field(
      @form_field,
      visibility_mode: params.require(:visibility_mode),
      required_mode: params.require(:required_mode)
    )
    redirect_to settings_forms_path(form: @form_field.incident_form_id)
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_forms_path(form: @form_field.incident_form_id),
      inertia: { errors: e.record.errors.to_hash }
  end

  def destroy
    form_id = @form_field.incident_form_id
    form_service.remove_field(@form_field)
    redirect_to settings_forms_path(form: form_id)
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
    form = current_workspace.incident_forms.find(params.require(:incident_form_id))
    ordered_ids = params.require(:ordered_ids)
    form_service.reorder(form, ordered_ids)
    redirect_to settings_forms_path(form: form.id)
  end

  private

  def set_form_field
    @form_field = IncidentFormField.joins(:incident_form)
      .where(incident_forms: { workspace_id: current_workspace.id })
      .find(params[:id])
  end

  def form_service
    @form_service ||= IncidentFormService.new(current_workspace)
  end
end
