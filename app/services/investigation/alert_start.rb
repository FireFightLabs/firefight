# Starts Halon on an incident an alert opened, once per alert group, since grouping makes one incident of a storm. The
# runs alerts start share a ceiling on what they may spend in an hour, so a storm of separate groups cannot run up a bill
# nobody is awake to see. A run gets what is left of it, up to the workspace's own budget, and none starts once too
# little is left. The incident is told whenever Halon does not start.
class Investigation::AlertStart
  OUTCOME_OFF = "off".freeze
  OUTCOME_STARTED = "started".freeze
  # A run on the incident was already live, as when someone started one first.
  OUTCOME_RUNNING = "running".freeze
  OUTCOME_HELD = "held".freeze

  # Returns what happened, one of the outcomes above.
  def self.start!(incident)
    workspace = incident.workspace
    return OUTCOME_OFF unless incident.source == Incident::SOURCE_ALERT && workspace.alert_investigations_enabled?
    return OUTCOME_RUNNING if incident.live_investigation

    refused = Investigation.start_refusal(workspace, incident)
    return held(incident, "Halon did not start on this alert. #{refused}", rerun: false) if refused

    outcome = workspace.transaction do
      workspace.lock_storm_budget!
      left = workspace.storm_budget_left_cents
      next OUTCOME_HELD if left < Workspace::OnCall::MIN_ALERT_RUN_CENTS

      started = InvestigationService.new(workspace).start(incident, trigger_source: Investigation::TRIGGER_ALERT, max_spend_cents: left)
      started ? OUTCOME_STARTED : OUTCOME_RUNNING
    end
    return outcome unless outcome == OUTCOME_HELD

    held(incident, ceiling_words(workspace), rerun: true)
  end

  def self.ceiling_words(workspace)
    "Halon did not start on this alert. Runs started by alerts in the last hour have used the #{workspace.shown_storm_ceiling} " \
      "they may spend in an hour, set under Halon, On-call. Start it here when you want it to look."
  end

  def self.held(incident, reason, rerun:)
    if incident.channel_id.present?
      WorkspaceAdapter.for(incident.workspace).post_alert_run_held(channel_id: incident.channel_id, incident: incident, reason: reason, rerun: rerun)
    end
    OUTCOME_HELD
  rescue AdapterError => error
    Rails.logger.warn({ event: "alert_run.held_untold", incident_id: incident.id, error: error.class.name }.to_json)
    OUTCOME_HELD
  end
  private_class_method :held, :ceiling_words
end
