# What a lifecycle form asks responders for, and changing it. A form has no
# stored row until something about it is changed, so reading one that has never
# been touched returns the workspace default rather than a not-found.
class Api::V1::FormsController < Api::V1::ApiController
  before_action :set_form, only: %i[show]

  def show
    authorize!(Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_READ)

    render :show
  end

  # Pass either custom_field or system_field to say which one you mean. Sending
  # conditions replaces the set on that field rather than adding to it.
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
