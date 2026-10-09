import { useState } from "react"

import { Card, CardContent } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { RESOURCE_MAP_INCIDENT_WINDOW_DAYS } from "@/lib/generated/constants"
import { ResourceRow } from "@/pages/map/components/resource-row"
import { linkCounts } from "@/pages/map/lib/link-counts"
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
      <Card className="overflow-hidden py-0">
        <CardContent className="overflow-x-auto p-0 [scrollbar-color:var(--border)_transparent] [scrollbar-width:thin]">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Resource</TableHead>
                <TableHead>Type</TableHead>
                <TableHead>Account</TableHead>
                <TableHead className="text-right">Depended on by</TableHead>
                <TableHead className="text-right">Links</TableHead>
                <TableHead>Runs</TableHead>
                <TableHead className="text-right">Incidents, {RESOURCE_MAP_INCIDENT_WINDOW_DAYS} days</TableHead>
                <TableHead>Last change</TableHead>
                <TableHead>Now</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={9} className="py-8 text-center text-sm text-muted-foreground">
                    {onlyAlone ? "Every resource here has at least one link." : "No resource matches these filters."}
                  </TableCell>
                </TableRow>
              )}
              {rows.map((resource) => (
                <ResourceRow key={resource.id} resource={resource} count={counts.get(resource.id)} onPick={onPick} />
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  )
}
