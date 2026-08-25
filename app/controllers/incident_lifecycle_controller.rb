# The dashboard's half of the incident lifecycle. Slack opens a modal built
# from the workspace's configured form, this renders the same form as HTML and
# posts it back. Both arrive at IncidentFormSubmission holding the same
# validated hashes, so neither surface can ask for something the other refuses.
class IncidentLifecycleController < InertiaController
  authorizes Ability::Action::RESOURCE_INCIDENTS,
    read: :form,
    update: %i[update assign_role reopen link]

  # The form as it stands given what has been answered so far. Re-fetched when
  # a dispatching field changes, because which fields apply is the resolver's
  # answer and never the browser's.
  def form
    incident = find_incident
    prompt = IncidentFormPrompt.new(
      current_workspace,
      incident: incident,
      form_slug: form_slug,
      answers: answers
    )

    render json: { fields: IncidentPromptFieldSerializer.many(prompt.fields) }
  end

  def update
    incident = find_incident
    member = current_member

    validated = IncidentFormResolver.new(current_workspace).validate_submission!(
      form_slug, answers, context: IncidentConditionEvaluator.context_for(incident)
    )
    submission = IncidentFormSubmission.new(
      current_workspace,
      incident: incident,
      form_slug: form_slug,
      system_attrs: validated[:system_attrs],
      custom_fields: validated[:custom_fields],
      visible_system_keys: visible_system_keys(incident)
    )

    attrs = submission.attributes
    attrs[:lead] = resolve_lead(submission.lead_value) if submission.lead_value

    IncidentLifecycleService.new(current_workspace).change_status(
      incident, attrs, changed_by: member, message: submission.message
    )

    redirect_to incident_path(incident), notice: confirmation(incident)
  rescue IncidentFormResolver::ValidationError => e
    redirect_to incident_path(incident), alert: e.field_errors.first
  rescue Incident::NotActive => e
    redirect_to incident_path(incident), alert: e.message
  end

  # One role at a time, cleared by omitting the member. The model owns whether
  # a role may change on this incident, so this never re-derives the rule.
  def assign_role
    incident = find_incident
    role = current_workspace.incident_roles.active.find_by!(slug: params.require(:role))
    member = params[:member_id].present? ? current_workspace.workspace_memberships.find(params[:member_id]) : nil

    IncidentLifecycleService.new(current_workspace).assign_role(incident, role, member, changed_by: current_member)

    redirect_to incident_path(incident), notice: role_confirmation(role, member)
  rescue IncidentLifecycleService::RoleNotUnassignable, Incident::NotActive => e
    redirect_to incident_path(incident), alert: e.message
  end

  # Not form-driven, the same as Slack: a reopened incident lands on the
  # workspace's default live status and carries the reason as its message.
  def reopen
    incident = find_incident
    return redirect_to(incident_path(incident), alert: "#{incident.identifier} is already active.") unless incident.terminal?

    IncidentLifecycleService.new(current_workspace).change_status(
      incident,
      { incident_status: current_workspace.default_live_status },
      changed_by: current_member,
      message: params[:reason].presence
    )

    redirect_to incident_path(incident), notice: "#{incident.identifier} was reopened."
  end

  def link
    incident = find_incident
    target = current_workspace.incidents.where(deleted_at: nil).find(params.require(:target_id))
    service = IncidentRelationshipService.new(current_workspace)

    if params.require(:relationship) == IncidentRelationship::DUPLICATE
      service.mark_duplicate(source: incident, canonical: target, created_by: current_member)
      notice = "#{incident.identifier} was marked as a duplicate of #{target.identifier}."
    else
      service.link_related(source: incident, target: target, created_by: current_member)
      notice = "#{incident.identifier} was linked to #{target.identifier}."
    end

    redirect_to incident_path(incident), notice: notice
  rescue ActiveRecord::RecordNotFound
    redirect_to incident_path(incident), alert: "Your workspace has no canceled status configured, so nothing can be marked a duplicate yet."
  end

  private

  def find_incident
    current_workspace.incidents.where(deleted_at: nil).find(params[:incident_id])
  end

  def current_member
    current_workspace.workspace_memberships.find_by!(user: current_user)
  end

  def form_slug
    slug = params.require(:form).to_s
    raise ActionController::BadRequest, "Unknown form" unless IncidentForm::SLUGS.include?(slug)

    slug
  end

  # Every key the workspace could ask about, scalars and the multi-valued
  # custom fields that arrive as lists. The resolver then rejects anything
  # this form did not actually ask for, so a permitted key is still not a
  # writable one.
  def answers
    raw = params[:answers]
    return {} if raw.blank?

    multi, scalar = custom_definitions.partition(&:multi_valued?).map { |group| group.map(&:slug) }
    scalar += IncidentSystemField::DEFINITIONS.map(&:key)

    raw.permit(*scalar, multi.to_h { |slug| [ slug, [] ] }).to_h
  end

  def custom_definitions
    @custom_definitions ||= current_workspace.incident_field_definitions.active.to_a
  end

  # Which system fields the form put in front of the responder, so blanking one
  # clears the attribute and a field that was never shown leaves it alone.
  def visible_system_keys(incident)
    IncidentFormResolver.new(current_workspace)
      .resolve(form_slug, context: IncidentConditionEvaluator.context_for(incident))
      .select(&:system?)
      .map(&:system_field_key)
      .to_set
  end

  def resolve_lead(member_id)
    current_workspace.workspace_memberships.find(member_id)
  end

  def confirmation(incident)
    case form_slug
    when IncidentForm::SLUG_RESOLVE then "#{incident.identifier} was resolved."
    when IncidentForm::SLUG_CANCEL then "#{incident.identifier} was canceled."
    else "#{incident.identifier} was updated."
    end
  end

  def role_confirmation(role, member)
    return "#{role.name} was cleared." if member.nil?

    "#{member.display_name} is now #{role.name}."
  end
end
