module Mcp
  # One of Firefight's tools as the MCP server lists it for a workspace: the class's own name,
  # description and annotations, with the workspace's choices filled into the parameters. A call
  # still goes to the class, which is what the dispatcher authorizes.
  class WorkspaceTool
    def initialize(tool_class, workspace)
      @tool_class = tool_class
      @workspace = workspace
    end

    def name = @tool_class.name_value

    def name_value = @tool_class.name_value

    def input_schema = ::MCP::Tool::InputSchema.new(@tool_class.schema_for(@workspace))

    def input_schema_value = input_schema

    def to_h = @tool_class.definition_for(@workspace)

    def call(server_context:, **args)
      @tool_class.call(server_context: server_context, **args)
    end
  end
end
