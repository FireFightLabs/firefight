import { IconExternalLink, IconPlayerPlay } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { workflowPath } from "@/lib/routes"
import { StatusPill } from "@/pages/halon/components/workflows/status-pill"
import { stateLabel, stateTone } from "@/pages/halon/components/workflows/labels"
import type { RunbookWorkflow } from "@/types/serializers"

export function RunbookWorkflowSummary({ workflow, onRun }: { workflow: RunbookWorkflow; onRun: () => void }) {
  return (
    <div className="flex flex-wrap items-center justify-between gap-3">
      <div className="flex min-w-0 flex-col gap-1">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium">{workflow.name}</span>
          <StatusPill label={stateLabel(workflow.state)} tone={stateTone(workflow.state)} />
        </div>
        <a
          href={workflowPath(workflow.id)}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-link hover:underline"
        >
          <IconExternalLink className="size-3.5" />
          Open the workflow
        </a>
      </div>
      <Blocked reason={workflow.runBlockedReason ?? undefined}>
        <Button size="sm" onClick={onRun} disabled={Boolean(workflow.runBlockedReason)}>
          <IconPlayerPlay className="size-3.5" />
          Run it
        </Button>
      </Blocked>
    </div>
  )
}
