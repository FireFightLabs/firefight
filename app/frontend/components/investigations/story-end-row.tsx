import { IconAlertTriangle, IconFlag, IconLoader2 } from "@tabler/icons-react"

import { AddNote } from "@/components/investigations/add-note"
import { StopRun } from "@/components/investigations/stop-run"
import { StoryIconMarker } from "@/components/investigations/story-icon-marker"
import { StoryRow } from "@/components/investigations/story-row"
import { isLive } from "@/components/investigations/use-live-investigation"
import type { InvestigationDetail } from "@/types/serializers"

// How the run ended, or that it is still working with a way to add a note or stop it.
export function StoryEndRow({ investigation }: { investigation: InvestigationDetail }) {
  if (isLive(investigation.status)) {
    return (
      <>
        <StoryRow
          marker={<IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
          tone="active"
          title={<span className="text-fg-secondary">Still working. This updates as it goes.</span>}
          aside={investigation.stopBlockedReason == null && <StopRun investigationId={investigation.id} />}
          connected={false}
        />
        {investigation.noteBlockedReason == null && (
          <li>
            <AddNote investigationId={investigation.id} />
          </li>
        )}
      </>
    )
  }
  if (investigation.finding) {
    return (
      <StoryRow
        marker={<StoryIconMarker icon={IconFlag} />}
        tone="success"
        title={<span className="font-medium text-fg-primary">Answered</span>}
        at={investigation.completedAt}
        connected={false}
      />
    )
  }
  return (
    <StoryRow
      marker={<StoryIconMarker icon={IconAlertTriangle} />}
      tone="warning"
      title={<span className="font-medium text-fg-primary">Stopped</span>}
      at={investigation.completedAt}
      connected={false}
    >
      <p className="text-sm text-fg-secondary">{investigation.stoppedBecause ?? "Stopped without an answer."}</p>
    </StoryRow>
  )
}
