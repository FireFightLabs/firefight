# Posts an update on an incident through the workspace's update form (post_incident_update), once, or again every few
# minutes while the incident is live, so its channel hears where things stand without anyone remembering to say it. A
# repeating step waits between updates and ends once the incident is resolved or cancelled. A message people have read
# cannot be taken back, so it carries no undo, and it is not held by a freeze or a read first, as a post to a channel is
# not.
class DefinedWorkflow::Steps::PostIncidentUpdate < DefinedWorkflow::Steps::FirefightTool
  kind "post_incident_update"
  label "Post incident update"
  group GROUP_INCIDENT
  config_help "incident (its identifier), message (markdown, may use references), every_minutes (optional, at least 5, to post again while " \
              "the incident is live). Outputs posted (how many it posted) and answer."

  KEY_MESSAGE = IncidentSystemField::KEY_MESSAGE
  KEY_EVERY = "every_minutes".freeze
  OUTPUT_POSTED = "posted".freeze
  CHECKPOINT_POSTED = "posted".freeze
  CHECKPOINT_NEXT = "next_at".freeze
  CHECKPOINT_ANSWER = "last_answer".freeze
  EVERY = (5..1_440)

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  KEY_INCIDENT = DefinedWorkflow::Steps::FirefightTool::KEY_INCIDENT

  class << self
    def tool_for(_config, _workspace) = Mcp::Tools::POST_INCIDENT_UPDATE

    def arguments_for(config, _workspace) = { KEY_INCIDENT => config[KEY_INCIDENT].to_s, "answers" => { KEY_MESSAGE => config[KEY_MESSAGE].to_s } }

    def undoable?(_config, _workspace) = false

    # Said once and never taken back, so there is nothing to check first.
    def checks_first?(_config, _workspace) = false

    def output_fields(_config) = [ OUTPUT_POSTED, OUTPUT_ANSWER ]

    def every(config) = config[KEY_EVERY].presence&.to_i

    def own_problems(config, named, _workspace)
      found = [ needs(config, KEY_INCIDENT, named, "the incident it posts on, such as {{trigger.incident.identifier}}"),
                needs(config, KEY_MESSAGE, named, "what it posts") ]
      minutes = config[KEY_EVERY]
      if minutes.present? && !(minutes.to_s.match?(/\A\d+\z/) && EVERY.cover?(minutes.to_i))
        found << "#{named} posts again every #{EVERY.first} to #{EVERY.last} minutes."
      end
      found.compact
    end

    def describe(config, _workspace)
      again = every(config) ? ", every #{every(config)} minutes while it is live" : ""
      "On #{config[KEY_INCIDENT]}#{again}: #{config[KEY_MESSAGE].to_s.squish}".truncate(200)
    end
  end

  def frozen = nil

  def perform
    return simulated_output(self.class.describe(@config, workspace)) if simulated?

    checkpoint = @step.reload.checkpoint.to_h
    posted = checkpoint[CHECKPOINT_POSTED].to_i
    if posted.positive?
      return finished(posted, checkpoint) unless incident_live?

      due = Time.zone.parse(checkpoint[CHECKPOINT_NEXT].to_s)
      return SolidWorkflow::Park.new(wake_at: due) if due && due > Time.current
    end

    held = checkpoint[CHECKPOINT_HELD]
    answer = held ? after_decision(held) : call(nil)
    return answer if answer.is_a?(SolidWorkflow::Park)

    posted += 1
    every = self.class.every(@config)
    following = every && Time.current + every.minutes
    write_checkpoint(CHECKPOINT_HELD => nil, CHECKPOINT_POSTED => posted, CHECKPOINT_NEXT => following&.iso8601, CHECKPOINT_ANSWER => answer[OUTPUT_ANSWER])
    return { OUTPUT_POSTED => posted, OUTPUT_ANSWER => answer[OUTPUT_ANSWER] } unless every && incident_live?

    SolidWorkflow::Park.new(wake_at: following)
  end

  private

  def finished(posted, checkpoint) = { OUTPUT_POSTED => posted, OUTPUT_ANSWER => checkpoint[CHECKPOINT_ANSWER] }

  def incident_live?
    incident = Mcp::Tools::GetIncident.find_by_reference(workspace.incidents.where(deleted_at: nil), @config[KEY_INCIDENT].to_s)
    incident.present? && !incident.terminal?
  end

  def write_checkpoint(values)
    SolidWorkflow::Step.where(id: @step.id).update_all([ "checkpoint = COALESCE(checkpoint, '{}'::jsonb) || ?::jsonb", values.to_json ])
  end
end
