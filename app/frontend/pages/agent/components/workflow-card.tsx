import { Link } from "@inertiajs/react"
import { IconLoader2, IconRepeat } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { CHAT_WORKFLOW_ACTIONS, WORKFLOW_RUN_QUERY_PARAM, WORKFLOW_RUN_STATUSES, type WorkflowRunStatus } from "@/lib/generated/constants"
import { agentChatWorkflowPressPath, workflowPath } from "@/lib/routes"
import { formatDateTime } from "@/lib/formatters"
import { pressWorkflow } from "@/pages/agent/lib/chat-updates"
import type { AgentChatWorkflow } from "@/types/serializers"

type ChatWorkflowAction = AgentChatWorkflow["offers"][number]["action"]

interface WorkflowCardProps {
  conversationId: string
  workflow: AgentChatWorkflow
}

const LABELS: Record<ChatWorkflowAction, string> = {
  [CHAT_WORKFLOW_ACTIONS.RUN_NOW]: "Run now",
  [CHAT_WORKFLOW_ACTIONS.CANCEL]: "Cancel",
  [CHAT_WORKFLOW_ACTIONS.TURN_OFF]: "Turn off",
}

// What confirming a stop says, beside a Keep it that leaves it as it is.
const CONFIRM_LABELS: Record<ChatWorkflowAction, string> = {
  [CHAT_WORKFLOW_ACTIONS.RUN_NOW]: "Run now",
  [CHAT_WORKFLOW_ACTIONS.CANCEL]: "Cancel workflow",
  [CHAT_WORKFLOW_ACTIONS.TURN_OFF]: "Turn off",
}

const RUN_WORDS: Record<WorkflowRunStatus, string> = {
  queued: "is about to start",
  running: "is running",
  waiting: "is waiting",
  paused: "is paused",
  succeeded: "succeeded",
  failed: "failed",
  cancelled: "was stopped",
}

function isRunStatus(status: string): status is WorkflowRunStatus {
  return (WORKFLOW_RUN_STATUSES as readonly string[]).includes(status)
}

function runWords(status: string) {
  return isRunStatus(status) ? RUN_WORDS[status] : status
}

// A workflow Halon made in this chat, such as "in 30 minutes check web": when it runs, how its last run went, and Run
// now and Cancel. The server ships what is offered and why each is blocked, said on that button, so the card decides
// nothing.
export function WorkflowCard({ conversationId, workflow }: WorkflowCardProps) {
  const [ sending, setSending ] = useState<ChatWorkflowAction | null>(null)
  const [ confirming, setConfirming ] = useState<ChatWorkflowAction | null>(null)

  function send(action: ChatWorkflowAction) {
    setSending(action)
    pressWorkflow(agentChatWorkflowPressPath(conversationId, workflow.id, action), { onFinish: doneSending })
  }

  function press(action: ChatWorkflowAction) {
    if (action === CHAT_WORKFLOW_ACTIONS.RUN_NOW) {
      send(action)
      return
    }
    setConfirming(action)
  }

  function confirmed() {
    if (confirming) {
      send(confirming)
    }
    setConfirming(null)
  }

  function cancelConfirm() {
    setConfirming(null)
  }

  function doneSending() {
    setSending(null)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Workflow">
      <div className="flex items-start gap-2">
        <IconRepeat className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <p className="text-[12.5px] font-medium text-ink-2">Workflow</p>
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">
            <Link href={workflowPath(workflow.id)} className="hover:underline">{workflow.name}</Link>
          </h3>
          <p className="text-[12.5px] text-ink-3">{workflow.waiting ?? workflow.triggerWords}</p>
          {workflow.nextRunAt && !workflow.oneOff && <p className="text-[12.5px] text-ink-3">Runs next {formatDateTime(workflow.nextRunAt)}</p>}
          {workflow.lastRun && (
            <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">
              <Link href={workflowPath(workflow.id, { [WORKFLOW_RUN_QUERY_PARAM]: workflow.lastRun.id })} className="hover:underline">The last run {runWords(workflow.lastRun.status)}</Link>
              {workflow.lastRun.error && `. ${workflow.lastRun.error}`}
            </p>
          )}
        </div>
      </div>
      {workflow.offers.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {workflow.offers.map((offer) => (
            <Blocked key={offer.action} reason={offer.blockedReason ?? undefined} side="top">
              <Button
                size="sm"
                variant={offer.action === CHAT_WORKFLOW_ACTIONS.RUN_NOW ? "primary" : "secondary"}
                disabled={offer.blockedReason != null || sending != null}
                onClick={() => press(offer.action)}
              >
                {sending === offer.action && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
                {LABELS[offer.action]}
              </Button>
            </Blocked>
          ))}
        </div>
      )}
      <ConfirmDeleteDialog
        open={confirming != null}
        title={`${confirming ? LABELS[confirming] : ""} ${workflow.name}?`}
        description={`${workflow.name} will not run again on its own. Its runs stay readable on its page.`}
        confirmLabel={confirming ? CONFIRM_LABELS[confirming] : undefined}
        cancelLabel="Keep it"
        onConfirm={confirmed}
        onCancel={cancelConfirm}
      />
    </section>
  )
}
