import { router } from "@inertiajs/react"
import { IconChevronRight } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import { cn } from "@/lib/utils"
import { formatDateTime } from "@/lib/formatters"
import { WORKFLOW_VERSION_STATUS } from "@/lib/generated/constants"
import { workflowVersionRestorePath } from "@/lib/routes"
import { CANVAS_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { WorkflowVersionRow } from "@/types/serializers"
import { useWorkflowAccess } from "@/pages/halon/hooks/use-workflow-access"

const STATUS_WORDS: Record<WorkflowVersionRow["status"], string> = { draft: "Draft", live: "Live", retired: "Was live", discarded: "Discarded" }
const STATUS_TONES: Record<WorkflowVersionRow["status"], string> = {
  draft: "border-border-strong text-fg-secondary",
  live: "border-brand-border bg-brand-tint text-brand",
  retired: "border-border text-fg-muted",
  discarded: "border-border text-fg-disabled",
}

interface VersionRowProps {
  workflowId: string
  version: WorkflowVersionRow
  onOpen: (versionId: string) => void
}

// One version in the history: its number and status, who made it and why, who published it, and every change that
// landed on it with who made it, opened by a click.
export function VersionRow({ workflowId, version, onOpen }: VersionRowProps) {
  const canEdit = useWorkflowAccess().build
  const [ open, setOpen ] = useState(version.status === WORKFLOW_VERSION_STATUS.DRAFT)
  const halonMade = version.edits.filter((edit) => edit.byHalon).length

  function toggle() {
    setOpen(!open)
  }

  function view() {
    onOpen(version.id)
  }

  function restore() {
    router.post(workflowVersionRestorePath(workflowId, version.id), {}, CANVAS_VISIT)
  }

  return (
    <li className="border border-border bg-surface-card">
      <div className="flex flex-wrap items-start gap-3 px-3.5 py-3">
        <button type="button" onClick={toggle} aria-expanded={open} className="flex min-w-0 flex-1 items-start gap-2.5 text-left">
          <IconChevronRight className={cn("mt-0.5 size-4 shrink-0 text-fg-muted transition-transform", open && "rotate-90")} />
          <span className="min-w-0 flex-1">
            <span className="flex flex-wrap items-center gap-2">
              <b className="text-[13px] font-semibold text-fg-headline">Version {version.number}</b>
              <span className={cn("rounded-full border px-2 py-px font-mono text-[10.5px]", STATUS_TONES[version.status])}>{STATUS_WORDS[version.status]}</span>
              {halonMade > 0 && <span className="rounded-full border border-halon-border bg-halon-tint px-2 py-px font-mono text-[10.5px] text-halon">{halonMade} by Halon</span>}
            </span>
            <span className="mt-1 block text-[12.5px] text-fg-secondary">
              {version.authorName}
              {version.reason ? `: ${version.reason}` : ""}
            </span>
            <span className="mt-0.5 block text-[11.5px] text-fg-muted">
              {version.publishedAt ? `Published by ${version.publishedByName ?? "someone"} ${formatDateTime(version.publishedAt)}` : `Started ${formatDateTime(version.createdAt)}`}
            </span>
          </span>
        </button>
        <div className="flex gap-2">
          <Button type="button" variant="outline" size="sm" className="h-7 text-xs" onClick={view}>Open</Button>
          {canEdit && version.status !== WORKFLOW_VERSION_STATUS.DRAFT && (
            <Blocked reason={version.restoreBlockedReason ?? undefined} side="left">
              <Button type="button" variant="outline" size="sm" className="h-7 text-xs" disabled={version.restoreBlockedReason != null} onClick={restore}>Restore</Button>
            </Blocked>
          )}
        </div>
      </div>
      {open && (
        <ol className="space-y-1.5 border-t border-border px-3.5 py-2.5 pl-10">
          {version.edits.length === 0 && <li className="text-xs text-fg-muted">No changes on it yet.</li>}
          {version.edits.map((edit) => (
            <li key={edit.id} className="text-xs">
              <span className={edit.byHalon ? "text-halon" : "text-fg-primary"}>{edit.sentence}</span>
              {edit.acceptedByName && <span className="text-fg-muted"> Accepted by {edit.acceptedByName}.</span>}
              {edit.reason && <span className="block text-fg-muted">{edit.reason}</span>}
              <span className="block text-[11px] text-fg-disabled">{formatDateTime(edit.createdAt)}</span>
            </li>
          ))}
        </ol>
      )}
    </li>
  )
}
