class IncidentsController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS,
    read: %i[show postmortem postmortem_revisions],
    update: %i[update_postmortem update_postmortem_status generate_postmortem start_blank_postmortem ai_rewrite_postmortem]

  def show
    incident = current_workspace.incidents
      .with_detail_associations
      .find(params[:id])

    render inertia: "incidents/index", props: {
      incident: IncidentDetailSerializer.one(incident),
      timelineEvents: InertiaRails.defer { TimelineEventSerializer.many(incident.timeline_events) },
      actions: InertiaRails.defer {
        IncidentActionSerializer.many(
          incident.incident_actions.active.includes(assignee: :user, created_by: :user)
        )
      },
      attachableRunbooks: attachable_runbooks(incident),
      hasPostmortem: incident.postmortem.present?,
      postmortemStatus: incident.postmortem&.status,
      postmortemGenerationState: incident.postmortem&.generation_state
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

  def generate_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    return redirect_to incident_path(incident), alert: "AI features are not available." unless defined?(FirefightAi)
    return redirect_to incident_postmortem_path(incident), alert: "Postmortem already exists." if incident.postmortem.present?
    unless incident.incident_status.closed?
      alert = if incident.canceled?
        "#{incident.identifier} was canceled, so it has no postmortem to write."
      else
        "Postmortems can be created once the incident is resolved."
      end
      return redirect_to incident_path(incident), alert: alert
    end

    gate = Entitlements.check(current_workspace, Entitlements::AI)
    return redirect_to incident_path(incident), alert: gate.message if gate.blocked?

    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    PostmortemGenerationJob.perform_later(incident.id, member.id) if Postmortem.start_generation!(incident, by: member)

    redirect_to incident_postmortem_path(incident)
  end

  def start_blank_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    return redirect_to incident_postmortem_path(incident) if incident.postmortem.present?
    return redirect_to incident_path(incident), alert: "Postmortems can be created once the incident is resolved." unless incident.incident_status.closed?

    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    Postmortem.start_blank!(incident, by: member)

    redirect_to incident_postmortem_path(incident)
  end

  def ai_rewrite_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    incident.postmortem or raise ActiveRecord::RecordNotFound

    return render json: { error: "AI features are not available." }, status: :unprocessable_entity unless defined?(FirefightAi)

    gate = Entitlements.check(current_workspace, Entitlements::AI)
    return render json: { error: gate.message }, status: :payment_required if gate.blocked?

    selected_html = params[:selected_html].to_s
    instruction = params[:instruction].to_s

    return render json: { error: "selected_html and instruction are required" }, status: :unprocessable_entity if selected_html.blank? || instruction.blank?

    rewritten = FirefightAi::PostmortemSectionRewriter
      .new(current_workspace)
      .rewrite(incident, selected_html: selected_html, instruction: instruction)

    render json: { rewritten_html: rewritten }
  end

  private

  def attachable_runbooks(incident)
    incident.attachable_runbooks.map { |runbook| { slug: runbook.slug, name: runbook.name } }
  end
end
