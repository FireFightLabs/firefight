# What people said in an incident's channel. Its own resource rather than part
# of incidents, because reading an incident and reading every message in it are
# different asks, and a grant made for one should not quietly buy the other.
class Api::V1::TranscriptsController < Api::V1::ApiController
  DEFAULT_MESSAGES = 100
  MAX_MESSAGES = 500

  def index
    authorize!(Ability::Action::RESOURCE_INCIDENT_TRANSCRIPTS, Ability::Action::ACTION_READ)

    blocked_reason = current_workspace.transcript_access_blocked_reason
    return render_blocked(blocked_reason) if blocked_reason

    @incident = current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
    @messages = page
    render :index
  end

  private

  # Newest last, because that is the order a conversation reads in, but paged
  # backwards from the end, because that is the part worth reading first.
  def page
    scope = @incident.incident_transcript_messages.kept.order(posted_at: :desc, message_id: :desc)
    scope = scope.where("posted_at < ?", cursor.posted_at) if params[:before].present?

    scope.limit(limit).includes(:workspace_membership).to_a.reverse
  end

  def cursor
    @incident.incident_transcript_messages.find_by!(message_id: params[:before])
  end

  def limit
    (params[:limit].presence || DEFAULT_MESSAGES).to_i.clamp(1, MAX_MESSAGES)
  end

  def render_blocked(reason)
    render json: error_response("transcript_access_disabled", reason), status: :forbidden
  end
end
