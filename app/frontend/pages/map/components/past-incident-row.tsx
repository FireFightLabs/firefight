import { Link } from "@inertiajs/react"

import { formatDate } from "@/lib/formatters"
import { incidentPath } from "@/lib/routes"
import type { ResourceMapPastIncident } from "@/types/serializers"

export function PastIncidentRow({ incident }: { incident: ResourceMapPastIncident }) {
  return (
    <Link href={incidentPath(incident.id)} className="flex flex-col gap-0.5 rounded-lg border border-border bg-background/50 px-3 py-2 text-sm hover:bg-muted/40">
      <span className="flex justify-between gap-3">
        <span className="font-semibold">{incident.identifier}</span>
        <span className="shrink-0 text-xs text-muted-foreground tabular-nums">{formatDate(incident.endedAt)}</span>
      </span>
      <span>{incident.name}</span>
      <span className="text-xs text-muted-foreground">
        {incident.outcome ? `${incident.outcomeSource}: ${incident.outcome}` : "Nothing was written about how it ended."}
      </span>
    </Link>
  )
}
