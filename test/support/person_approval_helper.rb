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

# The same over the REST API, for a test class about what such a call does. A request answered 202 approval_required is
# approved here as an admin would in the dashboard and sent again with its X-Approval-Id.
module ApprovesHeldApiCalls
  %i[post patch put delete].each do |verb|
    define_method(verb) do |path, **args|
      super(path, **args)
      return status unless status == 202 && response.parsed_body.dig("error", "type") == "approval_required"

      approval = Ability::Approval.find(response.parsed_body["approval_id"])
      approval.update!(status: Ability::Approval::STATUS_APPROVED, resolved_at: Time.current)
      super(path, **args, headers: (args[:headers] || {}).merge("X-Approval-Id" => approval.id))
    end
  end
end
