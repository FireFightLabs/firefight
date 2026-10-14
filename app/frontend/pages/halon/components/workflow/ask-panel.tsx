import { router } from "@inertiajs/react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { APPROVAL_STATUS, WORKFLOW_ASK_KIND, WORKFLOW_QUESTION_STATUS } from "@/lib/generated/constants"
import { workflowRunApprovalApprovePath, workflowRunApprovalDenyPath, workflowRunQuestionAnswerPath } from "@/lib/routes"
import { AnswerDialog } from "@/pages/halon/components/workflow/answer-dialog"
import { RUN_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowRunStep } from "@/types/serializers"

export type Ask = NonNullable<WorkflowRunStep["ask"]>

const OPEN = new Set<string>([ WORKFLOW_QUESTION_STATUS.OPEN, APPROVAL_STATUS.PENDING ])

interface AskPanelProps {
  workflowId: string
  runId: string
  ask: Ask
}

// What an Ask a person or Approval step asked, on the run's page: the question, who may answer, and, while it waits,
// its choices, Answer for a short form, or Approve and Deny. Each says why it cannot be pressed for someone who may not.
// Once settled it says who answered and how.
export function AskPanel({ workflowId, runId, ask }: AskPanelProps) {
  const [ answering, setAnswering ] = useState(false)
  const waiting = OPEN.has(ask.status)
  const blocked = ask.blockedReason ?? undefined
  const approval = ask.kind === WORKFLOW_ASK_KIND.APPROVAL

  function choose(choice: string) {
    router.post(workflowRunQuestionAnswerPath(workflowId, runId, ask.id), { choice }, RUN_VISIT)
  }

  function approve() {
    router.post(workflowRunApprovalApprovePath(workflowId, runId, ask.id), {}, RUN_VISIT)
  }

  function deny() {
    router.post(workflowRunApprovalDenyPath(workflowId, runId, ask.id), {}, RUN_VISIT)
  }

  function openAnswer() {
    setAnswering(true)
  }

  return (
    <section className="space-y-2 rounded-sm border border-border-strong px-2.5 py-2" aria-label={approval ? "Approval" : "Question"}>
      <p className="text-sm font-medium [overflow-wrap:anywhere]">{ask.question}</p>
      {ask.details && <p className="text-xs whitespace-pre-wrap text-fg-secondary [overflow-wrap:anywhere]">{ask.details}</p>}
      <p className="text-xs text-fg-muted">{approval ? `${ask.who} decides.` : `Asked of ${ask.who}.`}</p>
      {waiting && (
        <div className="flex flex-wrap gap-1.5">
          {approval && (
            <>
              <Blocked reason={blocked} side="top">
                <Button type="button" size="sm" disabled={blocked !== undefined} onClick={approve}>Approve</Button>
              </Blocked>
              <Blocked reason={blocked} side="top">
                <Button type="button" size="sm" variant="destructive" disabled={blocked !== undefined} onClick={deny}>Deny</Button>
              </Blocked>
            </>
          )}
          {!approval && ask.fields.length === 0 && ask.choices.map((choice) => (
            <Blocked key={choice.value} reason={blocked} side="top">
              <Button type="button" size="sm" variant="outline" disabled={blocked !== undefined} onClick={() => choose(choice.value)}>{choice.label}</Button>
            </Blocked>
          ))}
          {!approval && ask.fields.length > 0 && (
            <Blocked reason={blocked} side="top">
              <Button type="button" size="sm" disabled={blocked !== undefined} onClick={openAnswer}>Answer</Button>
            </Blocked>
          )}
        </div>
      )}
      {!waiting && <p className="text-xs text-fg-secondary whitespace-pre-wrap">{settledWords(ask)}</p>}
      {answering && <AnswerDialog workflowId={workflowId} runId={runId} ask={ask} open={answering} onOpenChange={setAnswering} />}
    </section>
  )
}

function settledWords(ask: Ask): string {
  if (ask.kind === WORKFLOW_ASK_KIND.APPROVAL) {
    if (ask.status === APPROVAL_STATUS.APPROVED) {
      return `Approved by ${ask.answeredBy ?? "an approver"}.`
    }
    if (ask.status === APPROVAL_STATUS.DENIED) {
      return `Denied by ${ask.answeredBy ?? "an approver"}.`
    }
    return "Withdrawn before anyone decided."
  }
  if (ask.status === WORKFLOW_QUESTION_STATUS.ANSWERED) {
    return `${ask.answeredBy ?? "Someone"} answered: ${ask.answered ?? ""}`
  }
  return "Withdrawn before anyone answered."
}
