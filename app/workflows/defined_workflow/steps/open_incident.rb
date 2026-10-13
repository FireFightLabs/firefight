# Declares an incident through the same path /ff declare and Halon take (declare_incident, IncidentLifecycleService),
# answering the workspace's declare form with a name, a summary, a severity, a type and any other field the form asks.
# It changes something, so it needs its undo, such as cancelling the incident.
class DefinedWorkflow::Steps::OpenIncident < DefinedWorkflow::Steps::FirefightTool
  kind "open_incident"
  label "Open incident"
  group GROUP_INCIDENT
  config_help "name, summary (optional), severity and type (by their slugs, optional, the form's defaults otherwise), fields (other answers " \
              "of the declare form by their keys, optional), undo. Outputs incident (its identifier, such as INC-42), answer and data."

  KEY_NAME = IncidentSystemField::KEY_NAME
  KEY_SUMMARY = IncidentSystemField::KEY_SUMMARY
  KEY_SEVERITY = IncidentSystemField::KEY_SEVERITY
  KEY_TYPE = IncidentSystemField::KEY_INCIDENT_TYPE
  KEY_FIELDS = "fields".freeze
  OUTPUT_INCIDENT = "incident".freeze

  # Read by the class's own methods, which do not see what the classes it extends define.
  OUTPUT_ANSWER = DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER
  OUTPUT_DATA = DefinedWorkflow::Steps::CallTool::OUTPUT_DATA

  class << self
    def tool_for(_config, _workspace) = Mcp::Tools::DECLARE_INCIDENT

    def arguments_for(config, _workspace)
      answers = config.slice(KEY_NAME, KEY_SUMMARY, KEY_SEVERITY, KEY_TYPE).compact_blank
      { "answers" => config[KEY_FIELDS].to_h.merge(answers) }
    end

    def output_fields(_config) = [ OUTPUT_INCIDENT, OUTPUT_ANSWER, OUTPUT_DATA ]

    def own_problems(config, named, _workspace)
      found = [ needs(config, KEY_NAME, named, "a name for the incident") ]
      found << "#{named} gives the form's other answers as named values." unless config.fetch(KEY_FIELDS, {}).is_a?(Hash)
      found.compact
    end

    def describe(config, _workspace) = "Declares #{config[KEY_NAME].presence || 'an incident'}".truncate(200)
  end

  private

  def handed_on(data) = { OUTPUT_INCIDENT => data["identifier"] }
end
