# Starts a Halon investigation of an incident, or of a problem nobody declared one for, and waits for what it finds: how
# it ended, its finding and how sure it is. It runs as any investigation does, as the investigator, and the workflow's
# own identity needs only to be allowed to start one. An incident that already has one running is waited on rather than
# started again. It only reads, so a test run starts it for real.
class DefinedWorkflow::Steps::Investigate < DefinedWorkflow::Steps::Base
  kind "investigate"
  label "Investigate"
  group GROUP_HALON
  config_help "incident (its identifier, optional), symptom (what is wrong, needed without an incident), names (services or repositories " \
              "mentioned, optional). Waits for the finding. Outputs status (succeeded or failed), finding, confidence (0 to 1), " \
              "suggests_incident, url and investigation_id."

  KEY_INCIDENT = "incident".freeze
  KEY_SYMPTOM = Investigation::Brief::KEY_SYMPTOM
  KEY_NAMES = Investigation::Brief::KEY_NAMES
  OUTPUT_STATUS = "status".freeze
  OUTPUT_FINDING = "finding".freeze
  OUTPUT_CONFIDENCE = "confidence".freeze
  OUTPUT_SUGGESTS_INCIDENT = "suggests_incident".freeze
  OUTPUT_URL = "url".freeze
  OUTPUT_ID = "investigation_id".freeze
  CHECKPOINT_INVESTIGATION = "investigation_id".freeze
  ACTION = Ability::Action.system_key(Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE)
  # How long it waits when the step sets no time limit of its own. An investigation runs for minutes.
  WAIT_LIMIT = 60.minutes
  # How often it looks again while it waits, in case the word that it finished was lost.
  LOOK_AGAIN = 5.minutes

  class << self
    def checks?(_config, _workspace) = true

    def output_fields(_config) = [ OUTPUT_STATUS, OUTPUT_FINDING, OUTPUT_CONFIDENCE, OUTPUT_SUGGESTS_INCIDENT, OUTPUT_URL, OUTPUT_ID ]

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      return [ "#{named} needs the incident it investigates, or a symptom saying what is wrong." ] if config[KEY_INCIDENT].to_s.strip.empty? && config[KEY_SYMPTOM].to_s.strip.empty?

      []
    end

    def reach(_config, workspace, **)
      action = Ability::Action.lookup(ACTION, workspace)
      action ? [ DefinedWorkflow::Reach::Needed.of_action(action) ] : []
    end

    def describe(config, _workspace) = [ config[KEY_INCIDENT].presence, config[KEY_SYMPTOM].presence ].compact.join(": ").truncate(200)
  end

  def perform
    id = @step.reload.checkpoint.to_h[CHECKPOINT_INVESTIGATION]
    investigation = id ? Investigation.find_by(id: id) : start
    raise Refused, "The investigation this step waited for is gone." unless investigation
    return ended(investigation) unless Investigation::LIVE_STATUSES.include?(investigation.reload.status)

    deadline = (@step.first_started_at || Time.current) + ActiveSupport::Duration.build(@step.timeout_seconds || WAIT_LIMIT.to_i)
    raise SolidWorkflow::TimeLimitReached, "The investigation was still going after #{(deadline - (@step.first_started_at || Time.current)).seconds.inspect}." if deadline <= Time.current

    SolidWorkflow::Park.new(signal_key: investigation.finished_signal, wake_at: [ deadline, Time.current + LOOK_AGAIN ].min)
  end

  private

  def incident
    reference = @config[KEY_INCIDENT].to_s
    return nil if reference.blank?

    found = workspace.incidents.where(deleted_at: nil).find_by_reference(reference)
    raise Refused, "No incident is #{reference}." unless found

    found
  end

  # Started as the workflow's own identity asking, through the gateway, or the one already running for the incident. The
  # investigation is in the name of whoever is behind the run, so it reaches no further than they could, and in the
  # workflow's own only when its trigger started it with nobody behind it.
  def start
    subject = incident
    brief = Investigation::Brief.from(@config.slice(KEY_SYMPTOM, KEY_NAMES), source: Investigation::Brief::SOURCE_WORKFLOW)
    refused = Investigation.start_refusal(workspace, subject)
    raise Refused, refused if refused

    agent_run = Workflow::AgentRun.new(run: @run, record: record)
    started = agent_run.tool_call(action_key: ACTION, params: { KEY_INCIDENT => subject&.identifier, KEY_SYMPTOM => @config[KEY_SYMPTOM] }.compact) do
      InvestigationService.new(workspace).start(subject, trigger_source: Investigation::TRIGGER_WORKFLOW, triggered_by: @run.asker || principal, brief: brief)
    end.value
    investigation = started || subject&.investigations&.where(status: Investigation::LIVE_STATUSES)&.order(:created_at)&.last
    raise Refused, Investigation.already_running_message(subject) unless investigation

    SolidWorkflow::Step.where(id: @step.id).update_all([ "checkpoint = COALESCE(checkpoint, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)",
                                                         CHECKPOINT_INVESTIGATION, investigation.id ])
    investigation
  rescue AbilityGateway::Denied
    raise Refused, agent_run.refusal(ACTION)
  end

  def ended(investigation)
    finding = investigation.finding
    {
      OUTPUT_STATUS => investigation.status, OUTPUT_FINDING => finding&.summary || investigation.error_summary,
      OUTPUT_CONFIDENCE => finding&.winning_hypothesis&.confidence&.to_f, OUTPUT_SUGGESTS_INCIDENT => finding&.suggests_incident || false,
      OUTPUT_URL => AppUrl.absolute(Rails.application.routes.url_helpers.investigation_path(investigation)), OUTPUT_ID => investigation.id
    }
  end
end
