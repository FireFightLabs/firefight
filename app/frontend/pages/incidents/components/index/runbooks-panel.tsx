import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import {
  IconChevronDown,
  IconChevronRight,
  IconCircleCheck,
  IconExternalLink,
} from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"
import {
  AttachRunbookDialog,
  type AttachableRunbook,
} from "@/pages/incidents/components/index/attach-runbook-dialog"
import { RUNBOOK_QUERY_PARAM } from "@/lib/generated/constants"
import { claimRunbookStepPath, settingsRunbooksPath } from "@/lib/routes"

type Runbook = Incident["runbooks"][number]

function progressLabel(runbook: Runbook): string {
  if (runbook.stepsCount === 0) {
    return "No steps"
  }
  if (runbook.doneCount === runbook.stepsCount) {
    return `All ${runbook.stepsCount} steps done`
  }
  return `${runbook.doneCount} of ${runbook.stepsCount} steps done`
}

function StepRow({
  step,
  runbook,
  incidentId,
  canEdit,
}: {
  step: Runbook["steps"][number]
  runbook: Runbook
  incidentId: string
  canEdit: boolean
}) {
  function claim() {
    router.post(claimRunbookStepPath(incidentId, runbook.id, step.id), {}, { preserveScroll: true })
  }

  return (
    <li className="flex items-start gap-2 py-1">
      <IconCircleCheck
        className={`mt-0.5 size-3.5 shrink-0 ${step.done ? "text-emerald-500 dark:text-emerald-400" : "text-muted-foreground/30"}`}
        strokeWidth={1.75}
        aria-hidden
      />
      <span className="min-w-0 flex-1">
        <span className={`block text-[12.5px] leading-snug ${step.done ? "text-muted-foreground/60 line-through" : "text-foreground"}`}>
          {step.title}
        </span>
        {step.assignee && <span className="text-[11px] text-muted-foreground/70">{step.assignee}</span>}
      </span>
      {canEdit && !step.done && !step.assignee && (
        <button
          type="button"
          onClick={claim}
          className="shrink-0 rounded text-[11px] text-muted-foreground underline-offset-2 hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Claim
        </button>
      )}
    </li>
  )
}

// Collapsed by default. Two attached runbooks of seven steps each would push
// everything below them off the page.
function RunbookEntry({
  runbook,
  incidentId,
  canEdit,
}: {
  runbook: Runbook
  incidentId: string
  canEdit: boolean
}) {
  const [open, setOpen] = useState(false)
  const Chevron = open ? IconChevronDown : IconChevronRight

  function toggle() {
    setOpen(!open)
  }

  return (
    <li className="flex flex-col gap-1">
      <div className="flex items-start gap-1.5">
        <button
          type="button"
          onClick={toggle}
          disabled={runbook.stepsCount === 0}
          aria-expanded={open}
          className="mt-0.5 shrink-0 rounded text-muted-foreground/70 hover:text-foreground disabled:opacity-40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <Chevron className="size-3.5" />
          <span className="sr-only">{open ? "Hide steps" : "Show steps"}</span>
        </button>
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1.5 text-[13px] leading-snug text-foreground">
            {/* The same target the timeline's runbook entry opens, so a
                runbook is one click from wherever it is named. */}
            <Link
              href={settingsRunbooksPath({ [RUNBOOK_QUERY_PARAM]: runbook.runbookId })}
              className="truncate hover:underline"
            >
              {runbook.name}
            </Link>
            {runbook.externalUrl && (
              <a
                href={runbook.externalUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="shrink-0 text-muted-foreground hover:text-foreground"
                aria-label={`Open ${runbook.name} runbook link`}
              >
                <IconExternalLink className="size-3.5" />
              </a>
            )}
          </p>
          <p className="text-xs text-muted-foreground/70">{progressLabel(runbook)}</p>
        </div>
      </div>

      {open && (
        <ul className="ml-[22px] flex flex-col border-l border-border pl-2.5">
          {runbook.steps.map((step) => (
            <StepRow
              key={step.id}
              step={step}
              runbook={runbook}
              incidentId={incidentId}
              canEdit={canEdit}
            />
          ))}
        </ul>
      )}
    </li>
  )
}

export function RunbooksPanel({
  runbooks,
  attachable,
  incidentId,
  canEdit,
}: {
  runbooks: Incident["runbooks"]
  attachable: AttachableRunbook[]
  incidentId: string
  canEdit: boolean
}) {
  return (
    <div className="rounded-xl border border-border bg-card px-5 py-4">
      <div className="mb-3 flex items-center justify-between">
        <h3 className="text-[12px] font-semibold uppercase tracking-[0.10em] text-foreground">Runbooks</h3>
        <AttachRunbookDialog incidentId={incidentId} runbooks={attachable} />
      </div>

      {runbooks.length === 0 ? (
        <p className="text-[13px] text-muted-foreground/70">
          None attached. Attach one to post its steps in the incident channel.
        </p>
      ) : (
        <ul className="flex flex-col gap-2.5">
          {runbooks.map((runbook) => (
            <RunbookEntry
              key={runbook.id}
              runbook={runbook}
              incidentId={incidentId}
              canEdit={canEdit}
            />
          ))}
        </ul>
      )}
    </div>
  )
}
