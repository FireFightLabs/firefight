# Changes one thing about an incident through the tool Halon and outside agents change it with: its status, severity,
# type or fields through the workspace's update form (post_incident_update, IncidentLifecycleService), its lead or a role
# (assign_incident_role), who is invited (invite_responders) or a runbook attached (attach_runbook). One step makes one
# change, so each is approved, undone and checked on its own. It changes something, so it needs its undo.
class DefinedWorkflow::Steps::UpdateIncident < DefinedWorkflow::Steps::FirefightTool
  KEY_CHANGE = "change".freeze
  KEY_STATUS = IncidentSystemField::KEY_STATUS
  KEY_SEVERITY = IncidentSystemField::KEY_SEVERITY
  KEY_TYPE = IncidentSystemField::KEY_INCIDENT_TYPE
  KEY_MEMBER = "member".freeze
  KEY_ROLE = "role".freeze
  KEY_MEMBERS = "members".freeze
  KEY_RUNBOOK = "runbook".freeze
  KEY_FIELDS = "fields".freeze
  KEY_MESSAGE = IncidentSystemField::KEY_MESSAGE

  CHANGE_STATUS = "status".freeze
  CHANGE_SEVERITY = "severity".freeze
  CHANGE_TYPE = "type".freeze
  CHANGE_FIELDS = "fields".freeze
  CHANGE_LEAD = "lead".freeze
  CHANGE_ROLE = "role".freeze
  CHANGE_INVITE = "invite".freeze
  CHANGE_RUNBOOK = "runbook".freeze
  CHANGES = [ CHANGE_STATUS, CHANGE_SEVERITY, CHANGE_TYPE, CHANGE_FIELDS, CHANGE_LEAD, CHANGE_ROLE, CHANGE_INVITE, CHANGE_RUNBOOK ].freeze
  # The changes the update form makes, each answering the form's field of the same meaning.
  FORM_ANSWERS = { CHANGE_STATUS => KEY_STATUS, CHANGE_SEVERITY => KEY_SEVERITY, CHANGE_TYPE => KEY_TYPE }.freeze
  FORM_CHANGES = [ *FORM_ANSWERS.keys, CHANGE_FIELDS ].freeze

  kind "update_incident"
  label "Update incident"
  group GROUP_INCIDENT
  config_help "incident (its identifier, usually {{trigger.incident.identifier}}), change (one of #{CHANGES.join(', ')}), then status, severity or type " \
              "(by slug), fields (named answers of the update form), member (email, for lead or role), role (an incident role's slug), members " \
              "(emails, for invite), runbook (its slug), message (optional words posted with a status, severity, type or fields change), undo."

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  OUTPUT_DATA = DefinedWorkflow::Steps::CallTool::OUTPUT_DATA
  KEY_INCIDENT = DefinedWorkflow::Steps::FirefightTool::KEY_INCIDENT

  class << self
    def tool_for(config, _workspace)
      case config[KEY_CHANGE]
      when CHANGE_LEAD, CHANGE_ROLE then Mcp::Tools::ASSIGN_INCIDENT_ROLE
      when CHANGE_INVITE then Mcp::Tools::INVITE_RESPONDERS
      when CHANGE_RUNBOOK then Mcp::Tools::ATTACH_RUNBOOK
      else Mcp::Tools::POST_INCIDENT_UPDATE
      end
    end

    def arguments_for(config, _workspace)
      incident = { KEY_INCIDENT => config[KEY_INCIDENT].to_s }
      case config[KEY_CHANGE]
      when CHANGE_LEAD then incident.merge(KEY_ROLE => IncidentRole::SLUG_INCIDENT_LEAD, KEY_MEMBER => config[KEY_MEMBER].to_s)
      when CHANGE_ROLE then incident.merge(KEY_ROLE => config[KEY_ROLE].to_s, KEY_MEMBER => config[KEY_MEMBER].to_s)
      when CHANGE_INVITE then incident.merge(KEY_MEMBERS => Array(config[KEY_MEMBERS]).map(&:to_s))
      when CHANGE_RUNBOOK then incident.merge(KEY_RUNBOOK => config[KEY_RUNBOOK].to_s)
      else incident.merge("answers" => answers(config))
      end
    end

    def answers(config)
      change = config[KEY_CHANGE]
      given = change == CHANGE_FIELDS ? config[KEY_FIELDS].to_h : config.slice(FORM_ANSWERS[change]).compact_blank
      given.merge(config.slice(KEY_MESSAGE).compact_blank)
    end

    def undoable?(_config, _workspace) = true

    def output_fields(_config) = [ OUTPUT_ANSWER, OUTPUT_DATA ]

    def own_problems(config, named, _workspace)
      found = [ needs(config, KEY_INCIDENT, named, "the incident it changes, such as {{trigger.incident.identifier}}") ]
      change = config[KEY_CHANGE].to_s
      return found.compact + [ "#{named} needs what it changes, one of #{CHANGES.join(', ')}." ] unless CHANGES.include?(change)

      found << needs(config, FORM_ANSWERS[change], named, "the #{change} it sets") if FORM_ANSWERS.key?(change)
      found << "#{named} needs the fields it sets, as named answers." if change == CHANGE_FIELDS && config[KEY_FIELDS].to_h.empty?
      found << needs(config, KEY_MEMBER, named, "who it makes #{change == CHANGE_LEAD ? 'lead' : 'take the role'}") if [ CHANGE_LEAD, CHANGE_ROLE ].include?(change)
      found << needs(config, KEY_ROLE, named, "the role it fills") if change == CHANGE_ROLE
      found << "#{named} needs who it invites." if change == CHANGE_INVITE && Array(config[KEY_MEMBERS]).empty?
      found << needs(config, KEY_RUNBOOK, named, "the runbook it attaches") if change == CHANGE_RUNBOOK
      found.compact
    end

    def describe(config, _workspace)
      change = config[KEY_CHANGE].to_s
      what = case change
      when *FORM_ANSWERS.keys then "Sets the #{change} of #{config[KEY_INCIDENT]} to #{config[FORM_ANSWERS[change]]}"
      when CHANGE_FIELDS then "Sets #{config[KEY_FIELDS].to_h.keys.to_sentence} on #{config[KEY_INCIDENT]}"
      when CHANGE_LEAD then "Makes #{config[KEY_MEMBER]} lead of #{config[KEY_INCIDENT]}"
      when CHANGE_ROLE then "Gives #{config[KEY_MEMBER]} the #{config[KEY_ROLE]} role on #{config[KEY_INCIDENT]}"
      when CHANGE_INVITE then "Invites #{Array(config[KEY_MEMBERS]).to_sentence} to #{config[KEY_INCIDENT]}"
      when CHANGE_RUNBOOK then "Attaches #{config[KEY_RUNBOOK]} to #{config[KEY_INCIDENT]}"
      else "Changes #{config[KEY_INCIDENT]}"
      end
      what.truncate(200)
    end
  end

  # A change through the update form says what changed in the incident's channel, in the step's words, or, when it gives
  # none, in words naming the workflow, since a workspace's form may ask for them.
  def arguments
    given = super
    return given unless FORM_CHANGES.include?(@config[KEY_CHANGE]) && @config[KEY_MESSAGE].to_s.strip.empty?

    given.merge("answers" => given["answers"].merge(KEY_MESSAGE => default_message))
  end

  private

  def default_message
    change = @config[KEY_CHANGE]
    return "#{@run.workflow.name} updated #{@config[KEY_FIELDS].to_h.keys.to_sentence}." if change == CHANGE_FIELDS

    "#{@run.workflow.name} set the #{change} to #{@config[FORM_ANSWERS[change]]}."
  end
end
