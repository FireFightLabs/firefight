# A step that calls one of Firefight's own tools, chosen by the kind from its config rather than named by the author,
# such as Update incident calling post_incident_update to change a severity. It is the same call a Call a tool step
# makes, so grants, approval rules, a freeze window, the read before a change nobody pressed, a test run's pretending
# and the activity log decide it the same way. A kind says which tool its config calls (tool_for), with which arguments
# (arguments_for), and what it hands on from the answer (handed_on).
class DefinedWorkflow::Steps::FirefightTool < DefinedWorkflow::Steps::CallTool
  KEY_INCIDENT = "incident".freeze

  class << self
    def tool_for(_config, _workspace) = raise(NotImplementedError, "#{name} must say which tool it calls")

    def arguments_for(_config, _workspace) = {}

    def changes?(config, workspace) = DefinedWorkflow::Reach.changes?(workspace, tool_for(config, workspace), arguments_for(config, workspace))

    def checks?(config, workspace) = !changes?(config, workspace)

    def reach(config, workspace) = DefinedWorkflow::Reach.for_tool(workspace, tool_for(config, workspace), arguments_for(config, workspace))

    def problems(step, workspace) = own_problems(step["config"].to_h, step["name"].presence || "A step", workspace) + undo_problems(step, workspace)

    def own_problems(_config, _named, _workspace) = []

    def describe(config, workspace)
      tool = tool_for(config, workspace)
      [ Chat::Tools.title_for(tool, workspace, arguments_for(config, workspace)), config[KEY_INCIDENT].presence ].compact.join(" ").truncate(200)
    end

    # A value a step needs, missing, as a sentence, or nil.
    def needs(config, key, named, words) = ("#{named} needs #{words}." if config[key].to_s.strip.empty?)
  end

  def tool_name = self.class.tool_for(@config, workspace)

  def arguments = self.class.arguments_for(@config, workspace)

  private

  def output_of(said)
    output = super
    output.merge(handed_on(output[OUTPUT_DATA].is_a?(Hash) ? output[OUTPUT_DATA] : {}))
  end

  # What the kind hands on from the tool's answer read as JSON, beside the answer itself.
  def handed_on(_data) = {}
end
