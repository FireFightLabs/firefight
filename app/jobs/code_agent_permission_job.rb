# Has Halon decide a step a coding agent asked permission for, outside the box's own request, which only waits for the
# decision. Not on the conversations queue, whose workers can all be held by the very chats waiting on these changes.
# A step this fails to decide is refused, so the agent is never left waiting out its whole run.
class CodeAgentPermissionJob < ApplicationJob
  queue_as :default

  def perform(permission_id)
    permission = CodeAgentPermission.find_by(id: permission_id)
    return unless permission

    begin
      CodeAgentPermissionService.decide!(permission)
    rescue StandardError
      permission.decide!(allow: false, reason: CodeAgentPermissionService::UNDECIDED, by: SystemAgent.investigator)
      raise
    end
  end
end
