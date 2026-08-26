# What people said in an incident's channel, gated by its own resource and by
# the workspace having turned access on.
class Api::V1::TranscriptsController < Api::V1::ApiController
  def index
    authorize!(Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS, Ability::Action::ACTION_READ)

    blocked_reason = current_workspace.transcript_access_blocked_reason
    return render_blocked(blocked_reason) if blocked_reason

    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
    @page = @incident.incident_transcript_messages.page(before: params[:before], limit: params[:limit])
    render :index
  end

  private

  def render_blocked(reason)
    render json: error_response("transcript_access_disabled", reason), status: :forbidden
  end
end
