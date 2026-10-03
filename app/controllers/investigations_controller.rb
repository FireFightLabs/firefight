# A run's own address, which is what Slack links to. A run is read over the page of what it is about, so this
# sends a run on an incident to that incident with the run open, and shows the run on its own otherwise.
class InvestigationsController < InertiaController
  PROP_INVESTIGATION = "investigation"

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show], create: %i[add_note stop apply_fix mark_fix_step_done undo_fix cancel_fix]

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
    plan = plan_of(investigation)

    blocked = Investigation::FixRunner.apply!(plan, by: current_membership, from: AbilityGateway::SOURCE_WEB)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::FixRunner::APPLYING
  end

  # Halon writes the undo of an applied fix, and a person applies it like the fix.
  def undo_fix
    investigation = current_workspace.investigations.seen.find(params[:id])
    plan = investigation.finding&.remediation_plan
    raise ActiveRecord::RecordNotFound unless plan

    blocked = Investigation::UndoWriter.request!(plan, by: current_membership)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::UndoWriter::WRITING
  end

  # Whoever may apply a fix may stop one, as Stop does for a run.
  def cancel_fix
    investigation = current_workspace.investigations.seen.find(params[:id])
    plan = plan_of(investigation)
    blocked = Investigation::FixRunner.cancel!(plan, by: current_membership)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::FixRunner.cancelled_message(plan)
  end

  def mark_fix_step_done
    investigation = current_workspace.investigations.seen.find(params[:id])
    step = Investigation::RemediationStep.find_by!(id: params[:step_id], plan_id: plans_of(investigation).map(&:id))

    blocked = Investigation::FixRunner.mark_done!(step, by: current_membership)
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: Investigation::FixRunner::MARKED_DONE
  end

  private

  # The run's fix, or its undo when the address names it.
  def plan_of(investigation)
    plans = plans_of(investigation)
    (params[:plan_id].present? ? plans.find { |plan| plan.id == params[:plan_id] } : plans.first) || raise(ActiveRecord::RecordNotFound)
  end

  def plans_of(investigation) = investigation.finding&.plans || []
end
