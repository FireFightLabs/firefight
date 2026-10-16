# A tool that changes permissions, a credential, an approval or a webhook waits over MCP for a person to approve it. A
# test about what such a tool does approves the held call as an admin would and makes the identical call again.
module PersonApprovalHelper
  HELD = /Approval required \(id: (?<id>[0-9a-f-]+)\)/

  def call_approved_by_a_person(tool:, server_context:, args:)
    response = Mcp::ToolDispatcher.call(tool: tool, server_context: server_context, args: args)
    held = Mcp::ToolDispatcher.text_of(response).match(HELD)
    return response unless held

    Ability::Approval.find(held[:id]).update!(status: Ability::Approval::STATUS_APPROVED, resolved_at: Time.current)
    Mcp::ToolDispatcher.call(tool: tool, server_context: server_context, args: args.merge(approval_id: held[:id]))
  end
end
