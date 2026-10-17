# Run it on a runbook. The run acts as the linked workflow's own identity whoever pressed it, and the caller authorized
# running workflows.
class RunbookRunService
  PAYLOAD_RUNBOOK = "runbook".freeze
  PAYLOAD_INCIDENT = "incident".freeze

  def initialize(runbook)
    @runbook = runbook
  end

  # confirmed_by is the person who confirmed the run on its card in a chat, whose yes also answers the steps they may approve.
  def start!(by:, inputs: {}, incident: nil, started_by_kind: Workflow::Run::STARTED_BY_PERSON, confirmed_by: nil)
    refusal = @runbook.run_blocked_reason(by)
    raise Workflow::Run::Refused, refusal if refusal

    WorkflowRunService.new(@runbook.workflow).start!(started_by_kind: started_by_kind, started_by: (by if by.is_a?(WorkspaceMembership)),
                                                     inputs: inputs.to_h, trigger_payload: payload(incident), confirmed_by: confirmed_by)
  end

  private

  def payload(incident)
    {
      PAYLOAD_RUNBOOK => { "name" => @runbook.name, "slug" => @runbook.slug },
      PAYLOAD_INCIDENT => incident && { "identifier" => incident.identifier, "name" => incident.name }
    }.compact
  end
end
