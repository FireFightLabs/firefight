module Mcp
  module Tools
    # Each tool listed with this workspace's own choices in its parameters. Calls still go to the class.
    def self.for_workspace(workspace)
      FirefightTools.available_in(workspace).map { |tool_class| WorkspaceTool.new(tool_class, workspace) }
    end
  end
end
