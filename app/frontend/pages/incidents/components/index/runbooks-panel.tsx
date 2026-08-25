import { Link } from "@inertiajs/react"
import { IconBook, IconExternalLink } from "@tabler/icons-react"

import type { Incident } from "@/pages/incidents/types"
import {
  AttachRunbookDialog,
  type AttachableRunbook,
} from "@/pages/incidents/components/index/attach-runbook-dialog"
import { RUNBOOK_QUERY_PARAM } from "@/lib/generated/constants"
import { settingsRunbooksPath } from "@/lib/routes"

function progressLabel(runbook: Incident["runbooks"][number]): string {
  if (runbook.stepsCount === 0) {
    return "No steps"
  }
  if (runbook.doneCount === runbook.stepsCount) {
    return `All ${runbook.stepsCount} steps done`
  }
  return `${runbook.doneCount} of ${runbook.stepsCount} steps done`
}

export function RunbooksPanel({
  runbooks,
  attachable,
  incidentId,
}: {
  runbooks: Incident["runbooks"]
  attachable: AttachableRunbook[]
  incidentId: string
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
            <li key={runbook.id} className="flex items-start gap-2.5">
              <IconBook className="mt-0.5 size-3.5 shrink-0 text-muted-foreground/70" aria-hidden />
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
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
