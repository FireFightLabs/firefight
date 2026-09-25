import { Link, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { formatDateTime } from "@/lib/formatters"
import { operatorIncidentPath, operatorIncidentsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { Pager } from "@/pages/operator/components/pager"
import { TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorIncidentRow } from "@/types/serializers"

interface IncidentsProps extends OperatorPageProps {
  incidents: OperatorIncidentRow[]
  page: number
  more: boolean
}

function pageHref(page: number) {
  return operatorIncidentsPath({ page })
}

export default function OperatorIncidents() {
  const { incidents, page, more } = usePage<IncidentsProps>().props

  return (
    <OperatorLayout title="Incidents">
      <PageHeading
        title="Incidents"
        lead="Every incident across every workspace, newest first. Open one to see everything Firefight did for it, in order, and to act on what failed."
      />
      <Card className="gap-0 overflow-hidden py-0">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Incident</TableHead>
              <TableHead>Workspace</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Declared</TableHead>
              <TableHead>Problems</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {incidents.map((incident) => (
              <TableRow key={incident.id}>
                <TableCell>
                  <Link href={operatorIncidentPath(incident.id)} className="flex flex-col hover:underline">
                    <span className="font-mono text-[13px]">{incident.identifier}</span>
                    <span className="text-muted-foreground max-w-80 truncate text-xs">{incident.name}</span>
                  </Link>
                </TableCell>
                <TableCell className="text-muted-foreground">{incident.workspaceName}</TableCell>
                <TableCell className="text-muted-foreground">{incident.status}</TableCell>
                <TableCell className="text-muted-foreground">{incident.declaredAt ? formatDateTime(incident.declaredAt) : "-"}</TableCell>
                <TableCell>
                  {incident.problems > 0 ? (
                    <span className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${TONE_CLASSES.rose}`}>
                      <span className="size-1.5 rounded-full bg-current" />
                      {incident.problems} failed
                    </span>
                  ) : (
                    <span className="text-muted-foreground text-xs">None</span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {incidents.length === 0 && <p className="text-muted-foreground px-4 py-10 text-center text-sm">No incidents yet.</p>}
        <Pager page={page} more={more} hrefFor={pageHref} />
      </Card>
    </OperatorLayout>
  )
}
