# A member's request to publish a workflow, as the admins see it waiting on the Workflows page.
class WorkflowPublishRequestSerializer < BaseSerializer
  object_as :request

  type :string
  def id = request.id

  type :string
  def workflow_id = request.workflow_id

  type :string
  def workflow_name = request.workflow.name

  type :string
  def requester_name = request.requester.display_name

  type :string, optional: true
  def requested_at = request.requested_at&.iso8601

  # What publishing would let the workflow's own identity do that it cannot yet.
  type "string[]"
  def would_grant = request.workflow.missing_reach(request.version).map(&:label)
end
