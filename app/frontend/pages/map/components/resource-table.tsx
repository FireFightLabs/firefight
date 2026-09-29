import { Link } from "@inertiajs/react"
import { useState } from "react"

import { Switch } from "@/components/ui/switch"
import { Label } from "@/components/ui/label"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { incidentPath } from "@/lib/routes"
import { changeLabel, KIND_LABELS } from "@/pages/map/lib/labels"
import { shortAgo } from "@/pages/map/lib/time"
import type { ResourceMapLink, ResourceMapResource } from "@/types/serializers"

interface ResourceTableProps {
  resources: ResourceMapResource[]
  links: ResourceMapLink[]
  onPick: (resourceId: string) => void
}

// Ranked by how much would stop if each one failed, so what matters most reads first.
export function ResourceTable({ resources, links, onPick }: ResourceTableProps) {
  const [ onlyAlone, setOnlyAlone ] = useState(false)
  const counts = linkCounts(links)
  const rows = resources
    .filter((resource) => !onlyAlone || !counts.has(resource.id))
    .sort((first, second) => second.dependentIds.length - first.dependentIds.length || first.name.localeCompare(second.name))

  return (
    <div className="flex flex-col gap-3 overflow-auto p-4 lg:p-6">
      <div className="flex items-center gap-2">
        <Switch id="only-alone" checked={onlyAlone} onCheckedChange={setOnlyAlone} />
        <Label htmlFor="only-alone" className="font-normal text-muted-foreground">Only resources with no links</Label>
      </div>
      <div className="overflow-x-auto rounded-xl border border-border [scrollbar-color:var(--border)_transparent] [scrollbar-width:thin]">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Resource</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Account</TableHead>
              <TableHead className="text-right">Depended on by</TableHead>
              <TableHead className="text-right">Links</TableHead>
              <TableHead>Runs</TableHead>
              <TableHead className="text-right">Incidents, 30 days</TableHead>
              <TableHead>Last change</TableHead>
              <TableHead>Now</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={9} className="py-8 text-center text-sm text-muted-foreground">
                  Every resource here has at least one link.
                </TableCell>
              </TableRow>
            )}
            {rows.map((resource) => (
              <ResourceRow key={resource.id} resource={resource} count={counts.get(resource.id)} onPick={onPick} />
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}

interface Count {
  facts: number
  suggested: number
}

function linkCounts(links: ResourceMapLink[]): Map<string, Count> {
  const counts = new Map<string, Count>()
  for (const link of links) {
    for (const id of [ link.fromId, link.toId ]) {
      const count = counts.get(id) ?? { facts: 0, suggested: 0 }
      if (link.unconfirmed) {
        count.suggested += 1
      } else {
        count.facts += 1
      }
      counts.set(id, count)
    }
  }
  return counts
}

function ResourceRow({ resource, count, onPick }: { resource: ResourceMapResource; count?: Count; onPick: (resourceId: string) => void }) {
  const incident = resource.openIncidents[0]

  function pick() {
    onPick(resource.id)
  }

  return (
    <TableRow className={incident ? "bg-destructive/5" : undefined}>
      <TableCell>
        <button type="button" onClick={pick} className="font-semibold hover:underline">
          {resource.name}
        </button>
      </TableCell>
      <TableCell className="text-muted-foreground">{KIND_LABELS[resource.kind]}</TableCell>
      <TableCell className="text-muted-foreground">{resource.providerName} · {resource.account}</TableCell>
      <TableCell className="text-right tabular-nums">{resource.dependentIds.length}</TableCell>
      <TableCell className="text-right tabular-nums">
        {count ? count.facts : <span className="text-muted-foreground">None found</span>}
        {count && count.suggested > 0 && <span className="text-primary"> +{count.suggested} suggested</span>}
      </TableCell>
      <TableCell className="text-muted-foreground">{resource.catalogEntries.map((entry) => entry.name).join(", ") || "-"}</TableCell>
      <TableCell className="text-right tabular-nums">{resource.recentIncidentCount}</TableCell>
      <TableCell className="text-muted-foreground">
        {resource.lastChange ? `${changeLabel(resource.lastChange)}, ${shortAgo(resource.lastChange.happenedAt)} ago` : "-"}
      </TableCell>
      <TableCell>
        {incident ? (
          <Link href={incidentPath(incident.id)} className="rounded-md bg-destructive px-2 py-0.5 text-xs font-semibold text-destructive-foreground">
            {incident.identifier} open
          </Link>
        ) : (
          <span className="text-muted-foreground">-</span>
        )}
      </TableCell>
    </TableRow>
  )
}
