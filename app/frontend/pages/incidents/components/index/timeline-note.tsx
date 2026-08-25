import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconDotsVertical, IconExternalLink, IconSparkles } from "@tabler/icons-react"

import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import type { TimelineEvent } from "@/pages/incidents/types"
import { dismissIncidentEventPath } from "@/lib/routes"

export type Milestone = NonNullable<TimelineEvent["milestone"]>

export type NoteAccent = "emerald" | "amber" | "rose" | "neutral"

// Colour carries meaning only where a kind changes how the incident reads.
// Everything else stays neutral so the timeline does not turn into a rainbow.
export const noteAccent: Record<Milestone["kind"], NoteAccent> = {
  hypothesis: "neutral",
  finding: "neutral",
  root_cause: "rose",
  mitigation: "emerald",
  decision: "neutral",
  blocker: "amber",
  impact: "neutral",
  recovery: "emerald",
}

export function NoteQuote({ milestone, withDivider }: { milestone: Milestone; withDivider: boolean }) {
  return (
    <div className={withDivider ? "mt-2 border-t border-border pt-2" : ""}>
      {/* Flush with the tag row beneath it. The AI-noted label already says
          this is quoted, so a rule and an indent only break the alignment. */}
      {milestone.quote && (
        <blockquote className="text-sm leading-relaxed text-muted-foreground whitespace-pre-line">
          {milestone.quote}
        </blockquote>
      )}
      <div className={`flex items-center gap-3 ${milestone.quote ? "mt-2" : ""}`}>
        <span className="inline-flex items-center gap-1 rounded bg-muted px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-muted-foreground">
          <IconSparkles className="size-3" strokeWidth={1.75} />
          AI-noted
        </span>
        {milestone.permalink && (
          <a
            href={milestone.permalink}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <IconExternalLink className="size-3.5" />
            Open in Slack
          </a>
        )}
      </div>
    </div>
  )
}

export function DismissNoteAction({
  event,
  incidentId,
}: {
  event: TimelineEvent
  incidentId: string
}) {
  const [confirming, setConfirming] = useState(false)

  function askToDismiss() {
    setConfirming(true)
  }

  function cancel() {
    setConfirming(false)
  }

  // Only the timeline comes back. A full reload would drop the deferred
  // timeline to its skeleton, collapse the page, and throw the reader to the
  // top of a long incident.
  function dismiss() {
    setConfirming(false)
    router.patch(dismissIncidentEventPath(incidentId, event.id), {}, {
      preserveScroll: true,
      only: [ "timelineEvents", "flash" ],
    })
  }

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button
            variant="ghost"
            size="icon"
            className="size-7 text-muted-foreground/60 hover:text-foreground"
          >
            <IconDotsVertical className="size-4" />
            <span className="sr-only">Note actions</span>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-40">
          <DropdownMenuItem variant="destructive" onClick={askToDismiss}>
            Dismiss note
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <ConfirmDeleteDialog
        open={confirming}
        title="Remove this note from the timeline?"
        description="The note stops appearing on the timeline, in the API, and in postmortem drafts. It is kept as a dismissed note so the correction stays visible."
        confirmLabel="Dismiss note"
        onConfirm={dismiss}
        onCancel={cancel}
      />
    </>
  )
}
