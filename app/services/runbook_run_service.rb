# Run it on a runbook. The run acts as the linked workflow's own identity whoever pressed it, and the caller authorized
# running workflows.
class RunbookRunService
  PAYLOAD_RUNBOOK = "runbook".freeze
  PAYLOAD_INCIDENT = "incident".freeze

  def initialize(runbook)
    @runbook = runbook
  end

  def start!(by:, inputs: {}, incident: nil, started_by_kind: Workflow::Run::STARTED_BY_PERSON)
    refusal = @runbook.run_blocked_reason(by)
    raise Workflow::Run::Refused, refusal if refusal

    WorkflowRunService.new(@runbook.workflow).start!(started_by_kind: started_by_kind, started_by: (by if by.is_a?(WorkspaceMembership)),
                                                     inputs: inputs.to_h, trigger_payload: payload(incident))
  end

  private

  def payload(incident)
    {
      PAYLOAD_RUNBOOK => { "name" => @runbook.name, "slug" => @runbook.slug },
      PAYLOAD_INCIDENT => incident && { "identifier" => incident.identifier, "name" => incident.name }
    }.compact
  end
end
