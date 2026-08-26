class IncidentEscalationWorkflow < SolidWorkflow::Base
  workflow_name "incident.escalation.v1"

  step :post_escalation_message
  step :post_escalation_announcement_thread
  step :post_escalation_direct_message

  def post_escalation_message(workflow:, step:, input:)
    checkpointed(step) { service(workflow).post_escalation_message(workflow.subject, event: event(workflow)) }
  end

  def post_escalation_announcement_thread(workflow:, step:, input:)
    checkpointed(step) do
      service(workflow).post_escalation_announcement_thread(workflow.subject, event: event(workflow))
    end
  end

  def post_escalation_direct_message(workflow:, step:, input:)
    checkpointed(step) { service(workflow).post_escalation_direct_message(workflow.subject, event: event(workflow)) }
  end

  private

  # Everything an escalation message says is already on its event: who asked,
  # who was asked, and why. Carrying copies in the context would let them drift.
  def event(workflow)
    @event ||= workflow.subject.incident_events.find(workflow.context["escalation_event_id"])
  end

  def service(workflow)
    @service ||= IncidentUpdateService.new(workflow.subject.workspace)
  end
end
