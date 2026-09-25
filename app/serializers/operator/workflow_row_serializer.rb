module Operator
  # A workflow run for the console list.
  class WorkflowRowSerializer < BaseSerializer
    object_as :workflow

    STATE_UNION = WorkflowRuns::STATES.map(&:inspect).join(" | ")

    type :string
    def id = workflow.id

    type :string
    def workflow_class = workflow.workflow_class

    type STATE_UNION
    def state = workflow.state

    # An incident subject is named by its identifier and workspace, any other subject by its type.
    type :string
    def subject_label
      subject = workflow.subject
      return "#{subject.identifier} · #{subject.workspace.name}" if subject.is_a?(Incident)

      subject.respond_to?(:name) ? "#{workflow.subject_type} · #{subject.name}" : workflow.subject_type
    end

    type :string, optional: true
    def incident_id = (workflow.subject_id if workflow.subject_type == Incident.name)

    type :number
    def steps_done = workflow.steps.count { |step| step.succeeded? || step.skipped? }

    type :number
    def steps_total = workflow.steps.size

    type :string, optional: true
    def failed_step = workflow.steps.find(&:failed?)&.name

    type :string
    def created_at = workflow.created_at.utc.iso8601
  end
end
