# A fix applied on an incident is part of the incident's story, so applying it, each step's ending, a step a person
# did, cancelling it and writing its undo are on the incident's timeline, beside the run that found it. A fix on a run
# with no incident has no timeline to go on.
module Investigation::RemediationPlan::Timeline
  extend ActiveSupport::Concern

  def record_fix_applied!
    count = steps.size
    note_fix!(IncidentEvent::FIX_APPLIED, actor: acting_principal, message: "#{count} #{'step'.pluralize(count)}. #{summary}")
  end

  def record_fix_cancelled!
    note_fix!(IncidentEvent::FIX_CANCELLED, actor: cancelled_by)
  end

  # Once each time the fix ends (FixRunner claims it). A cancelled fix said so when it was cancelled, and its steps that
  # still ran are on the timeline on their own.
  def record_fix_ended!
    return if cancelled?

    current = steps.to_a
    done = current.count(&:done?)
    stopped = current.count { |step| [ Investigation::RemediationStep::STATUS_FAILED, Investigation::RemediationStep::STATUS_DECLINED ].include?(step.status) }
    words = "#{done} of #{current.size} #{'step'.pluralize(current.size)} done."
    unless status == Investigation::RemediationPlan::STATUS_APPLIED
      words = [ "Stopped partway.", words, ("#{stopped} did not go through." if stopped.positive?) ].compact.join(" ")
    end
    note_fix!(IncidentEvent::FIX_ENDED, actor: acting_principal, message: words, status: status)
  end

  # Recorded on the undo, which Halon wrote.
  def record_undo_written!
    note_fix!(IncidentEvent::FIX_UNDO_WRITTEN, actor: finding.investigation.acting_principal, message: summary)
  end

  # A step Firefight ran that went through, already held, failed or was declined. One that was skipped never ran.
  def record_step_ended!(step)
    if step.done?
      note_step!(IncidentEvent::FIX_STEP_DONE, step, actor: acting_principal, result: step.result_line)
    elsif Investigation::RemediationStep::STOPPED.include?(step.status) && step.status != Investigation::RemediationStep::STATUS_SKIPPED
      note_step!(IncidentEvent::FIX_STEP_FAILED, step, actor: acting_principal, result: step.failure_line)
    end
  end

  def record_step_marked_done!(step)
    note_step!(IncidentEvent::FIX_STEP_MARKED_DONE, step, actor: step.done_by, result: step.result_line)
  end

  private

  def note_step!(event_type, step, actor:, result:)
    note_fix!(event_type, actor: actor, step_id: step.id, position: step.position, step_title: step.shown_title, result: result,
                          link_label: step.outcome_label, link_url: step.outcome_url)
  end

  # A timeline entry never stops the fix, so one that cannot be written is logged and the fix goes on.
  def note_fix!(event_type, actor:, **details)
    incident = finding.investigation.incident
    return unless incident

    incident.incident_events.create!(
      event_type: event_type, actor: actor,
      metadata: { investigation_id: finding.investigation_id, plan_id: id, undo: undo? || nil, **details }.compact
    )
  rescue ActiveRecord::ActiveRecordError => error
    Rails.logger.warn({ event: "fix.timeline_not_noted", plan_id: id, event_type: event_type, error: error.class.name }.to_json)
    nil
  end
end
