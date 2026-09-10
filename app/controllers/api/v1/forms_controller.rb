# A form has no row until changed, so reading an untouched one returns the
# workspace default rather than a not-found.
class Api::V1::FormsController < Api::V1::ApiController
  before_action :set_form, only: %i[show]

  def show
    authorize!(Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_READ)

    render :show
  end

  # Pass custom_field or system_field to say which. Sending conditions replaces the set.
  def update
    authorize!(Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_UPDATE)

    @form, @form_field = IncidentFormService.new(current_workspace).upsert_field!(form_params)

    render :field, status: :ok
  end

  private

  def form_params
    params.permit(:custom_field, :system_field, :visible, :required,
                  conditions: [ :condition_field, :operator, :custom_field, values: [] ])
          .to_h.deep_symbolize_keys.merge(form: params[:id])
  end

  def set_form
    slug = params[:id].to_s
    unless IncidentForm::SLUGS.include?(slug)
      raise ActionController::BadRequest, "Unknown form #{slug.inspect}. Valid: #{IncidentForm::SLUGS.join(', ')}"
    end

    @form = current_workspace.incident_forms.find_by(slug: slug) ||
      IncidentForm.new(workspace: current_workspace, **IncidentForm::DEFAULTS_BY_SLUG.fetch(slug))
  end
end
