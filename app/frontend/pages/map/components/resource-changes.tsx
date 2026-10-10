import { WhatChanged } from "@/components/what-changed"
import { resourceMapResourceChangesPath } from "@/lib/routes"
import { shortAgo } from "@/lib/time"
import { changeLabel } from "@/pages/map/lib/labels"
import type { ResourceMapChange } from "@/types/serializers"

// What changed around a resource over the last week, led by the last change the map saw, for a glance.
export function ResourceChanges({ resourceId, lastChange }: { resourceId: string; lastChange?: ResourceMapChange }) {
  function pathFor(reads: number): string {
    return reads > 0 ? resourceMapResourceChangesPath(resourceId, { live: reads }) : resourceMapResourceChangesPath(resourceId)
  }

  const glance = lastChange && (
    <div className="flex justify-between gap-3 text-sm">
      <span>{changeLabel(lastChange)}</span>
      <span className="shrink-0 text-muted-foreground tabular-nums">{shortAgo(lastChange.happenedAt)} ago</span>
    </div>
  )

  return <WhatChanged pathFor={pathFor} quiet={quietSentence(lastChange)} glance={glance} />
}

function quietSentence(lastChange?: ResourceMapChange): string {
  if (!lastChange) {
    return "Nothing Firefight holds changed in the last week."
  }
  return `Nothing Firefight holds changed in the last week. The last change seen was ${changeLabel(lastChange)}, ${shortAgo(lastChange.happenedAt)} ago.`
}
