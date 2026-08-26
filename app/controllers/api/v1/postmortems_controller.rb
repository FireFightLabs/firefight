# The write-up of an incident, over REST. Creating one is refused until the
# incident is resolved, which the incident itself decides.
class Api::V1::PostmortemsController < Api::V1::ApiController
  before_action :set_incident
  before_action :set_postmortem, only: %i[show update]

  def show
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_READ)

    render :show
  end

  # Passing generate drafts it from the incident, which takes a moment, so the
  # response comes back with a generation_state to poll on.
  def create
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    blocked_reason = @incident.postmortem_blocked_reason
    return render_blocked(blocked_reason) if blocked_reason

    ActiveModel::Type::Boolean.new.cast(params[:generate]) ? generate! : start_blank!

    @postmortem = @incident.reload.postmortem
    render :show, status: :created
  end

  # Sending html replaces the body rather than appending to it, and every
  # version is kept.
  def update
    authorize!(Ability::Action::RESOURCE_INCIDENTS, Ability::Action::ACTION_UPDATE)

    @postmortem.update_content!(params[:html], by: Current.principal) if params.key?(:html)
    @postmortem.update_status!(params.require(:status), by: Current.principal) if params.key?(:status)

    @postmortem.reload
    render :show
  end

  private

  def start_blank!
    Postmortem.start_blank!(@incident, by: Current.principal)
  end

  def generate!
    raise ActionController::BadRequest, "AI features are not available." unless defined?(FirefightAi)

    gate = Entitlements.check(current_workspace, Entitlements::AI)
    raise ActionController::BadRequest, gate.message if gate.blocked?

    PostmortemGenerationJob.perform_later(@incident.id) if Postmortem.start_generation!(@incident, by: Current.principal)
  end

  def render_blocked(reason)
    render json: error_response("incident_not_active", reason), status: :unprocessable_entity
  end

  def set_incident
    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end

  def set_postmortem
    @postmortem = @incident.postmortem or raise ActiveRecord::RecordNotFound
  end
end
