class IncidentsController < InertiaController
  before_action :require_authentication

  def show
    incident = current_workspace.incidents
      .with_detail_associations
      .find(params[:id])

    render inertia: "incidents/index", props: {
      incident: IncidentDetailSerializer.one(incident),
      timelineEvents: InertiaRails.defer {
        TimelineEventSerializer.many(
          incident.incident_events.chronological.includes(:actor, eventable: nil)
        )
      },
      actions: InertiaRails.defer {
        IncidentActionSerializer.many(
          incident.incident_actions.active.includes(assignee: :user, created_by: :user)
        )
      },
      hasPostmortem: incident.postmortem.present?,
      postmortemStatus: incident.postmortem&.status
    }
  end

  def postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    postmortem = incident.postmortem

    render inertia: "incidents/postmortem", props: {
      incident: {
        id: incident.id,
        identifier: incident.identifier,
        name: incident.name
      },
      postmortem: postmortem ? PostmortemSerializer.one(postmortem) : nil
    }
  end

  def update_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    postmortem = incident.postmortem or raise ActiveRecord::RecordNotFound
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    postmortem.update_content!(params[:html_content], by: member)

    head :ok
  end

  def update_postmortem_status
    incident = current_workspace.incidents.find(params[:incident_id])
    postmortem = incident.postmortem or raise ActiveRecord::RecordNotFound
    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    postmortem.update_status!(params.require(:status), by: member)

    redirect_to incident_postmortem_path(incident)
  end

  def postmortem_revisions
    incident = current_workspace.incidents.find(params[:incident_id])
    postmortem = incident.postmortem or raise ActiveRecord::RecordNotFound

    revisions = postmortem.postmortem_updates.order(created_at: :desc).includes(edited_by: :user)
    render json: PostmortemUpdateSerializer.many(revisions)
  end

  def ai_rewrite_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    incident.postmortem or raise ActiveRecord::RecordNotFound

    selected_html = params[:selected_html].to_s
    instruction = params[:instruction].to_s

    return render json: { error: "selected_html and instruction are required" }, status: :unprocessable_entity if selected_html.blank? || instruction.blank?

    rewritten = FirefightAi::PostmortemSectionRewriter
      .new(current_workspace)
      .rewrite(incident, selected_html: selected_html, instruction: instruction)

    render json: { rewritten_html: rewritten }
  end
end
