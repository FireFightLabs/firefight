class Api::V1::CustomFieldsController < Api::V1::ApiController
  before_action :set_custom_field, only: %i[update destroy]

  def index
    authorize!(Ability::Action::RESOURCE_CUSTOM_FIELDS, Ability::Action::ACTION_READ)
    @custom_fields = current_workspace.incident_field_definitions.active.ordered
  end

  # Options are matched by label, so resending a list renames rather than
  # replaces, and the incidents already holding an option keep pointing at it.
  def create
    authorize!(Ability::Action::RESOURCE_CUSTOM_FIELDS, Ability::Action::ACTION_CREATE)

    @custom_field = field_service.upsert!(nil, field_params)
    render :show, status: :created
  end

  def update
    authorize!(Ability::Action::RESOURCE_CUSTOM_FIELDS, Ability::Action::ACTION_UPDATE)

    @custom_field = field_service.upsert!(@custom_field, field_params)
    render :show
  end

  def destroy
    authorize!(Ability::Action::RESOURCE_CUSTOM_FIELDS, Ability::Action::ACTION_DELETE)

    blocked_reason = @custom_field.deletion_blocked_reason
    return render json: error_response("validation_error", blocked_reason), status: :unprocessable_entity if blocked_reason

    @custom_field.destroy!
    head :no_content
  end

  private

  def field_service
    @field_service ||= IncidentFieldDefinitionService.new(current_workspace)
  end

  def field_params
    params.permit(:name, :description, :field_type, :option_source, :catalog_type, options: []).to_h.symbolize_keys
  end

  def set_custom_field
    @custom_field = current_workspace.incident_field_definitions.active.find_by!(slug: params[:id])
  end
end
