import { Link, usePage } from "@inertiajs/react"
import { IconPlayerPause, IconPlayerPlay, IconPlayerStop } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card } from "@/components/ui/card"
import { formatDateTime, formatTime } from "@/lib/formatters"
import { OPERATOR_STEP_STATUSES } from "@/pages/operator/generated/constants"
import {
  cancelOperatorWorkflowPath,
  operatorIncidentPath,
  operatorWorkflowsPath,
  pauseOperatorWorkflowPath,
  resumeOperatorWorkflowPath,
} from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { useAction } from "@/pages/operator/hooks/use-action"
import { WorkflowState } from "@/pages/operator/components/workflow-state"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorWorkflow } from "@/types/serializers"
import { StepGraph } from "@/pages/operator/components/step-graph"
import { StepDetail } from "@/pages/operator/components/step-detail"

interface WorkflowProps extends OperatorPageProps {
  workflow: OperatorWorkflow
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
          <Link href={operatorIncidentPath(workflow.incidentId)} className="text-link hover:underline">
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
          <p className="text-fg-muted mb-3 text-[10.5px] font-medium tracking-[0.18em] uppercase">Events</p>
          {workflow.events.length === 0 ? (
            <p className="text-muted-foreground text-sm">No events recorded.</p>
          ) : (
            <ol className="flex flex-col">
              {workflow.events.map((event) => (
                <li key={event.id} className="grid grid-cols-[70px_minmax(0,1fr)] gap-3 border-b border-border/60 py-2 text-sm last:border-0">
                  <time dateTime={event.at} className="text-muted-foreground font-mono text-xs">{formatTime(event.at)}</time>
                  <div className="flex min-w-0 flex-col gap-0.5">
                    <span className={`font-mono text-xs ${event.failed ? "text-error" : ""}`}>
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
        description="Its steps that have not run are canceled and do not run. A canceled workflow cannot be resumed."
        confirmLabel="Cancel workflow"
        onConfirm={cancel}
        onCancel={stopAsking}
      />
    </OperatorLayout>
  )
}
