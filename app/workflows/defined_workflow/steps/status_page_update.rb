# Posts or updates a status page through a connected tool whose provider hosts its customers' status pages (the
# registry's holds_status_pages), with the run's data in it. It is a Call a tool step limited to those tools that change
# something, so grants, approval rules, a freeze window, the read before a change nobody pressed and the activity log
# decide it the same way, and it needs its undo, such as posting that the incident is resolved.
class DefinedWorkflow::Steps::StatusPageUpdate < DefinedWorkflow::Steps::CallTool
  kind "status_page_update"
  label "Status page update"
  group GROUP_MESSAGES
  config_help "tool (a tool of a connected status page provider that changes something, such as one that posts a status report), " \
              "arguments (its arguments, values may be references), undo. Outputs answer and data."

  # Read by the class's own methods, which do not see what the classes it extends define.
  KEY_TOOL = DefinedWorkflow::Steps::CallTool::KEY_TOOL

  class << self
    # A tool that changes something on a connection whose provider hosts status pages.
    def status_page_tool?(workspace, name)
      tool = workspace.connection_tools_by_name[name.to_s]
      tool.present? && !tool.read_only? && IntegrationProvider.find(tool.integration.provider)&.holds_status_pages == true
    end

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      return [ "#{named} needs the status page tool it calls." ] if config[KEY_TOOL].to_s.strip.empty?
      unless status_page_tool?(workspace, config[KEY_TOOL])
        return [ "#{named} calls #{config[KEY_TOOL]}, which is not a tool of a connected status page that changes something." ]
      end

      super
    end

    def undoable?(_config, _workspace) = true

    def checks?(_config, _workspace) = false
  end
end
