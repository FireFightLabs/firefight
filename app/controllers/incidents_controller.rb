class IncidentsController < InertiaController
  LINKABLE_LIMIT = 50

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
          IncidentAction.with_actors(incident.incident_actions.active.includes(:assignee, :created_by).to_a)
        )
      },
      attachableRunbooks: attachable_runbooks(incident),
      # The platform owns what a link to its own channel looks like, so the
      # page is handed the finished URL rather than assembling one.
      channelUrl: WorkspaceAdapter.for(current_workspace).channel_url(channel_id: incident.channel_id),
      linkableIncidents: linkable_incidents(incident),
      memberChoices: member_choices,
      hasPostmortem: incident.postmortem.present?,
      postmortemStatus: incident.postmortem&.status,
      postmortemGenerationState: incident.postmortem&.generation_state
    }
  end

  # Everything else still open or recently closed, for linking and marking a
  # duplicate. Capped, since the picker searches rather than scrolls.
  def linkable_incidents(incident)
    current_workspace.incidents
      .where(deleted_at: nil)
      .where.not(id: incident.id)
      .recent
      .limit(LINKABLE_LIMIT)
      .map { |other| { id: other.id, identifier: other.identifier, name: other.name } }
  end

  # Who a role can be handed to. The lead picker and the roles panel both read
  # this rather than each fetching the roster.
  def member_choices
    current_workspace.workspace_memberships.includes(:user)
      .map { |member| { value: member.id, label: member.display_name } }
      .sort_by { |choice| choice[:label] }
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

    postmortem.update_content!(params[:html_content], by: member, expected_version: params[:version])

    render json: { version: postmortem.reload.content_version }
  rescue Postmortem::StaleContent
    render json: {
      error: "Somebody else changed this postmortem while you were editing. Reload to see their version."
    }, status: :conflict
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

    blocked_reason = incident.postmortem_blocked_reason
    return redirect_to incident_path(incident), alert: blocked_reason if blocked_reason

    gate = Entitlements.check(current_workspace, Entitlements::AI)
    return redirect_to incident_path(incident), alert: gate.message if gate.blocked?

    member = current_workspace.workspace_memberships.find_by!(user: current_user)

    PostmortemGenerationJob.perform_later(incident.id) if Postmortem.start_generation!(incident, by: member)

    redirect_to incident_postmortem_path(incident)
  end

  def start_blank_postmortem
    incident = current_workspace.incidents.find(params[:incident_id])
    return redirect_to incident_postmortem_path(incident) if incident.postmortem.present?

    blocked_reason = incident.postmortem_blocked_reason
    return redirect_to incident_path(incident), alert: blocked_reason if blocked_reason

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
