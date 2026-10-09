import { Link } from "@inertiajs/react"

import { TableCell, TableRow } from "@/components/ui/table"
import { incidentPath } from "@/lib/routes"
import { KIND_LABELS } from "@/lib/resource-map-kinds"
import { shortAgo } from "@/lib/time"
import { changeLabel } from "@/pages/map/lib/labels"
import type { LinkCount } from "@/pages/map/lib/link-counts"
import type { ResourceMapResource } from "@/types/serializers"

export function ResourceRow({ resource, count, onPick }: { resource: ResourceMapResource; count?: LinkCount; onPick: (resourceId: string) => void }) {
  const burning = resource.openIncidents.length > 0

  function pick() {
    onPick(resource.id)
  }

  return (
    <TableRow className={burning ? "bg-destructive/5" : undefined}>
      <TableCell>
        <button type="button" onClick={pick} className="font-semibold hover:underline">
          {resource.name}
        </button>
      </TableCell>
      <TableCell className="text-muted-foreground">{KIND_LABELS[resource.kind]}</TableCell>
      <TableCell className="text-muted-foreground">{resource.providerName} · {resource.account}</TableCell>
      <TableCell className="text-right tabular-nums">
        {resource.dependentIds.length}
        {resource.suggestedDependentIds.length > 0 && <span className="text-brand"> +{resource.suggestedDependentIds.length} suggested</span>}
      </TableCell>
      <TableCell className="text-right tabular-nums">
        {count ? count.facts : <span className="text-muted-foreground">None found</span>}
        {count && count.suggested > 0 && <span className="text-brand"> +{count.suggested} suggested</span>}
      </TableCell>
      <TableCell className="text-muted-foreground">{resource.catalogEntries.map((entry) => entry.name).join(", ") || "-"}</TableCell>
      <TableCell className="text-right tabular-nums">{resource.recentIncidentCount}</TableCell>
      <TableCell className="text-muted-foreground">
        {resource.lastChange ? `${changeLabel(resource.lastChange)}, ${shortAgo(resource.lastChange.happenedAt)} ago` : "-"}
      </TableCell>
      <TableCell>
        {burning ? (
          <span className="flex flex-wrap gap-1.5">
            {resource.openIncidents.map((incident) => (
              <Link key={incident.id} href={incidentPath(incident.id)} className="rounded-md bg-destructive px-2 py-0.5 text-xs font-semibold text-destructive-foreground">
                {incident.identifier} open
              </Link>
            ))}
          </span>
        ) : (
          <span className="text-muted-foreground">-</span>
        )}
      </TableCell>
    </TableRow>
  )
}
