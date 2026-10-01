# A run's own address, which is what Slack links to. A run is read over the page of what it is about, so this
# sends a run on an incident to that incident with the run open, and shows the run on its own otherwise.
class InvestigationsController < InertiaController
  PROP_INVESTIGATION = "investigation"

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show], create: %i[add_note stop apply_fix mark_fix_step_done]

  def show
    investigation = current_workspace.investigations.seen.find(params[:id])
    incident = investigation.incident
    return redirect_to incident_path(incident, Investigation::QUERY_PARAM => investigation.id) if incident

    render inertia: "investigations/investigation", props: {
      PROP_INVESTIGATION => InvestigationDetailSerializer.one(investigation)
    }
  end

  # A responder steering a run while it works. Whoever may start a run may add to one.
  def add_note
    investigation = current_workspace.investigations.seen.find(params[:id])
    text = params[:note].to_s
    blocked = investigation.note_blocked_reason(text)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    investigation.add_note!(text.strip, by: current_membership)
    redirect_back_or_to investigation_path(investigation), notice: Investigation::Noting::NOTE_ADDED
  end

  # Whoever may start a run may stop one, as Slack's own stop button allows anyone in the thread.
  def stop
    investigation = current_workspace.investigations.seen.find(params[:id])
    blocked = investigation.stop_blocked_reason
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    investigation.request_cancel!
    redirect_back_or_to investigation_path(investigation), notice: Investigation::STOPPING
  end

  # The fix's steps run as whoever applies it, so whoever may start a run may apply its fix, and each step is still the
  # gateway's to allow.
  def apply_fix
    investigation = current_workspace.investigations.seen.find(params[:id])
    plan = investigation.finding&.remediation_plan
    raise ActiveRecord::RecordNotFound unless plan

    blocked = Investigation::FixRunner.apply!(plan, by: current_membership, from: AbilityGateway::SOURCE_WEB)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::FixRunner::APPLYING
  end

  def mark_fix_step_done
    investigation = current_workspace.investigations.seen.find(params[:id])
    step = investigation.finding&.remediation_plan&.steps&.find(params[:step_id])
    raise ActiveRecord::RecordNotFound unless step

    blocked = Investigation::FixRunner.mark_done!(step, by: current_membership)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::FixRunner::MARKED_DONE
  end
end
