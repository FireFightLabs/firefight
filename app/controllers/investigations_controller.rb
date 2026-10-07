# A run's own address, which is what Slack links to. A run is read over the page of what it is about, so this
# sends a run on an incident to that incident with the run open, and shows the run on its own otherwise.
class InvestigationsController < InertiaController
  PROP_INVESTIGATION = "investigation"

  include ServesChatAttachment

  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, read: %i[show file rate], create: %i[start add_note stop apply_fix mark_fix_step_done undo_fix cancel_fix run_fix_step dismiss_fix_step ask_fix_step_again]

  def show
    investigation = current_workspace.investigations.seen.find(params[:id])
    incident = investigation.incident
    return redirect_to incident_path(incident, Investigation::QUERY_PARAM => investigation.id) if incident

    render inertia: "investigations/investigation", props: {
      PROP_INVESTIGATION => InvestigationDetailSerializer.one(investigation)
    }
  end

  # The Investigate button on an incident's page. The run opens over the incident, where its story shows each step.
  def start
    incident = current_workspace.incidents.find(params[:incident_id])
    refusal = Investigation.unavailable_reason(current_workspace) || incident.investigation_start_blocked_reason
    return redirect_to(incident_path(incident), alert: refusal) if refusal

    started = InvestigationService.new(current_workspace).start(
      incident, trigger_source: Investigation::TRIGGER_DASHBOARD, triggered_by: current_membership
    )
    unless started
      return redirect_to(incident_path(incident), alert: incident.investigation_start_blocked_reason || "Halon could not start on #{incident.identifier}. Try again.")
    end

    redirect_to incident_path(incident, Investigation::QUERY_PARAM => started.id), notice: "Halon is investigating #{incident.identifier}."
  end

  # Right, partly right or wrong, as Slack's buttons rate it. Whoever may read the run may rate its answer, and may change
  # their mind.
  def rate
    investigation = current_workspace.investigations.seen.find(params[:id])
    finding = investigation.finding
    outcome = params[:outcome].to_s
    raise ActiveRecord::RecordNotFound unless finding && Investigation::Finding::OUTCOMES.include?(outcome)

    finding.record_verdict!(outcome, by: current_membership)
    redirect_back_or_to investigation_path(investigation), notice: Investigation::Finding.verdict_recorded(outcome)
  end

  # A file that went with a note, for whoever may read the run, the same bytes and headers as a chat's file.
  def file
    investigation = current_workspace.investigations.seen.find(params[:id])
    send_chat_attachment(investigation.note_file(params[:file_id]))
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

  # Approving a step never ran it. Only this runs it, once, as whoever applied the fix.
  def run_fix_step
    decide_fix_step("Running the step now.") { |step| Investigation::FixRunner.run_approved!(step, by: current_membership) }
  end

  def dismiss_fix_step
    decide_fix_step("Dismissed. The step will not run.") { |step| Investigation::FixRunner.dismiss_approved!(step, by: current_membership) }
  end

  def ask_fix_step_again
    decide_fix_step("Asked for approval again.") { |step| Investigation::FixRunner.ask_again!(step, by: current_membership) }
  end

  private

  def decide_fix_step(done)
    investigation = current_workspace.investigations.seen.find(params[:id])
    step = Investigation::RemediationStep.find_by!(id: params[:step_id], plan_id: plans_of(investigation).map(&:id))

    blocked = yield step
    return redirect_back_or_to(investigation_path(investigation), alert: blocked) if blocked

    redirect_back_or_to investigation_path(investigation), notice: done
  end

  # The run's fix, or its undo when the address names it.
  def plan_of(investigation)
    plans = plans_of(investigation)
    (params[:plan_id].present? ? plans.find { |plan| plan.id == params[:plan_id] } : plans.first) || raise(ActiveRecord::RecordNotFound)
  end

  def plans_of(investigation) = investigation.finding&.plans || []
end
