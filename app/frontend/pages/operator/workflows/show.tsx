import { Link, usePage } from "@inertiajs/react"
import { IconCheck, IconClock, IconPlayerPause, IconPlayerPlay, IconPlayerStop, IconX, type Icon } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { OPERATOR_STEP_STATUSES } from "@/lib/generated/constants"
import {
  cancelOperatorWorkflowPath,
  operatorIncidentPath,
  operatorWorkflowsPath,
  pauseOperatorWorkflowPath,
  resumeOperatorWorkflowPath,
} from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { StepActions } from "@/pages/operator/components/step-actions"
import { useAction } from "@/pages/operator/lib/use-action"
import { WorkflowState } from "@/pages/operator/components/workflow-state"
import { STEP_STATUS_TONES, TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorWorkflow } from "@/types/serializers"

type Step = OperatorWorkflow["steps"][number]

interface WorkflowProps extends OperatorPageProps {
  workflow: OperatorWorkflow
}

const NODE_WIDTH = 200
const NODE_HEIGHT = 52
const COLUMN_GAP = 44
const ROW_GAP = 18

function statusIcon(status: Step["status"]): Icon {
  if (status === OPERATOR_STEP_STATUSES.SUCCEEDED) {
    return IconCheck
  }
  if (status === OPERATOR_STEP_STATUSES.FAILED) {
    return IconX
  }
  return IconClock
}

function place(step: Step) {
  return { left: step.column * (NODE_WIDTH + COLUMN_GAP), top: step.row * (NODE_HEIGHT + ROW_GAP) }
}

// An edge from each step to every step it waits for. Edges into a failed step are drawn in rose.
function StepGraph({ steps, selected, onSelect }: { steps: Step[]; selected: string | null; onSelect: (id: string) => void }) {
  const byName = new Map(steps.map((step) => [step.name, step]))
  const width = (Math.max(0, ...steps.map((step) => step.column)) + 1) * (NODE_WIDTH + COLUMN_GAP)
  const height = (Math.max(0, ...steps.map((step) => step.row)) + 1) * (NODE_HEIGHT + ROW_GAP)
  const edges = steps.flatMap((step) =>
    step.dependsOn.flatMap((name) => {
      const from = byName.get(name)
      if (!from) {
        return []
      }
      const start = place(from)
      const end = place(step)
      const x1 = start.left + NODE_WIDTH
      const y1 = start.top + NODE_HEIGHT / 2
      const x2 = end.left
      const y2 = end.top + NODE_HEIGHT / 2
      const middle = (x1 + x2) / 2
      return [{ key: `${name}-${step.name}`, path: `M${x1} ${y1} C${middle} ${y1}, ${middle} ${y2}, ${x2} ${y2}`, failed: step.status === OPERATOR_STEP_STATUSES.FAILED }]
    }),
  )

  return (
    <div className="overflow-x-auto">
      <div className="relative" style={{ width, height }}>
        <svg width={width} height={height} className="absolute inset-0" aria-hidden>
          {edges.map((edge) => (
            <path key={edge.key} d={edge.path} fill="none" strokeWidth={1.5} className={edge.failed ? "stroke-rose-400/60" : "stroke-muted-foreground/35"} />
          ))}
        </svg>
        {steps.map((step) => {
          const StatusIcon = statusIcon(step.status)
          const position = place(step)
          return (
            <button
              key={step.id}
              type="button"
              onClick={() => onSelect(step.id)}
              aria-pressed={selected === step.id}
              className={`absolute flex flex-col justify-center gap-0.5 rounded-lg border px-3 text-left transition-shadow ${TONE_CLASSES[STEP_STATUS_TONES[step.status]]} ${selected === step.id ? "ring-2 ring-primary/60" : ""}`}
              style={{ ...position, width: NODE_WIDTH, height: NODE_HEIGHT }}
            >
              <span className="flex items-center gap-1.5 font-mono text-xs font-medium text-foreground">
                <StatusIcon className="size-3.5 shrink-0" stroke={2} />
                <span className="truncate">{step.name}</span>
              </span>
              <span className="text-[11px] opacity-80">
                {step.status}
                {step.seconds != null && ` · ${step.seconds} s`}
                {step.attempts > 1 && ` · ${step.attempts} tries`}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function StepDetail({ step }: { step: Step }) {
  return (
    <div className="flex flex-col gap-3">
      <p className="text-muted-foreground/75 text-[10.5px] font-medium tracking-[0.18em] uppercase">Selected step</p>
      <p className="font-mono text-sm font-medium">{step.name}</p>
      <dl className="grid grid-cols-[90px_minmax(0,1fr)] gap-x-3 gap-y-2 text-sm">
        <dt className="text-muted-foreground">Status</dt>
        <dd className="capitalize">{step.status}</dd>
        <dt className="text-muted-foreground">Attempts</dt>
        <dd className="font-mono">{step.attempts} of {step.maxAttempts ?? "-"}</dd>
        <dt className="text-muted-foreground">Took</dt>
        <dd className="font-mono">{step.seconds != null ? `${step.seconds} s` : "-"}</dd>
        <dt className="text-muted-foreground">Waits for</dt>
        <dd className="font-mono text-xs">{step.dependsOn.length > 0 ? step.dependsOn.join(", ") : "nothing"}</dd>
      </dl>
      {step.skipReason && <p className="text-muted-foreground text-sm">{step.skipReason}</p>}
      {step.lastError && (
        <pre className="bg-muted/40 max-h-64 overflow-auto rounded-md border border-border p-3 font-mono text-xs whitespace-pre-wrap text-rose-300">{step.lastError}</pre>
      )}
      {step.actionBlockedReason === null && <StepActions stepId={step.id} stepName={step.name} />}
    </div>
  )
}

export default function OperatorWorkflowPage() {
  const { workflow } = usePage<WorkflowProps>().props
  const firstFailed = workflow.steps.find((step) => step.status === OPERATOR_STEP_STATUSES.FAILED)
  const [selectedId, setSelectedId] = useState<string | null>(firstFailed?.id ?? workflow.steps[0]?.id ?? null)
  const [confirmingCancel, setConfirmingCancel] = useState(false)
  const { busy, post } = useAction()
  const selected = workflow.steps.find((step) => step.id === selectedId) ?? null

  function pause() {
    post(pauseOperatorWorkflowPath(workflow.id))
  }

  function resume() {
    post(resumeOperatorWorkflowPath(workflow.id))
  }

  function askToCancel() {
    setConfirmingCancel(true)
  }

  function stopAsking() {
    setConfirmingCancel(false)
  }

  function cancel() {
    setConfirmingCancel(false)
    post(cancelOperatorWorkflowPath(workflow.id))
  }

  return (
    <OperatorLayout title={workflow.workflowClass}>
      <Link href={operatorWorkflowsPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All workflows
      </Link>
      <PageHeading
        title={<span className="font-mono">{workflow.workflowClass}</span>}
        lead={`Started ${formatDateTime(workflow.createdAt)} for ${workflow.subjectLabel}. ${workflow.stepsDone} of ${workflow.stepsTotal} steps done.`}
      >
        {!workflow.pauseBlockedReason && (
          <Button type="button" variant="outline" onClick={pause} disabled={busy}>
            <IconPlayerPause className="size-4" />
            Pause
          </Button>
        )}
        {!workflow.resumeBlockedReason && (
          <Button type="button" variant="outline" onClick={resume} disabled={busy}>
            <IconPlayerPlay className="size-4" />
            Resume
          </Button>
        )}
        {!workflow.cancelBlockedReason && (
          <Button type="button" variant="outline" onClick={askToCancel} disabled={busy}>
            <IconPlayerStop className="size-4" />
            Cancel
          </Button>
        )}
      </PageHeading>
      <div className="mb-6 flex flex-wrap items-center gap-3 text-sm">
        <WorkflowState state={workflow.state} />
        {workflow.incidentId && (
          <Link href={operatorIncidentPath(workflow.incidentId)} className="text-primary hover:underline">
            Open the incident's timeline
          </Link>
        )}
        {workflow.pauseReason && <span className="text-muted-foreground">{workflow.pauseReason}</span>}
        {workflow.cancellationReason && <span className="text-muted-foreground">{workflow.cancellationReason}</span>}
      </div>
      <Card className="gap-0 p-6">
        <StepGraph steps={workflow.steps} selected={selectedId} onSelect={setSelectedId} />
      </Card>
      <div className="mt-6 grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)]">
        <Card className="gap-0 p-5">{selected ? <StepDetail step={selected} /> : <p className="text-muted-foreground text-sm">No steps.</p>}</Card>
        <Card className="gap-0 p-6">
          <p className="text-muted-foreground/75 mb-3 text-[10.5px] font-medium tracking-[0.18em] uppercase">Events</p>
          {workflow.events.length === 0 ? (
            <p className="text-muted-foreground text-sm">No events recorded.</p>
          ) : (
            <ol className="flex flex-col">
              {workflow.events.map((event) => (
                <li key={event.id} className="grid grid-cols-[70px_minmax(0,1fr)] gap-3 border-b border-border/60 py-2 text-sm last:border-0">
                  <time dateTime={event.at} className="text-muted-foreground font-mono text-xs">{formatTime(event.at)}</time>
                  <div className="flex min-w-0 flex-col gap-0.5">
                    <span className={`font-mono text-xs ${event.failed ? "text-rose-400" : ""}`}>
                      {event.eventType}
                      {event.stepName && <span className="text-muted-foreground"> {event.stepName}</span>}
                    </span>
                    {event.note && <span className="text-muted-foreground text-xs">{event.note}</span>}
                  </div>
                </li>
              ))}
            </ol>
          )}
        </Card>
      </div>
      <ConfirmDeleteDialog
        open={confirmingCancel}
        title={`Cancel ${workflow.workflowClass}?`}
        description="Its steps that have not run are cancelled and do not run. A cancelled workflow cannot be resumed."
        confirmLabel="Cancel workflow"
        onConfirm={cancel}
        onCancel={stopAsking}
      />
    </OperatorLayout>
  )
}
