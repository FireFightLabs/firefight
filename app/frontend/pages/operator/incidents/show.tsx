import { Link, usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { operatorIncidentsPath } from "@/lib/routes"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import { TONE_CLASSES } from "@/pages/operator/lib/tone"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorIncidentRow, OperatorProcessEntry } from "@/types/serializers"
import { ProcessEntryRow } from "@/pages/operator/components/process-entry-row"

interface IncidentProps extends OperatorPageProps {
  incident: OperatorIncidentRow
  entries: OperatorProcessEntry[]
  total: number
}

export default function OperatorIncident() {
  const { incident, entries, total } = usePage<IncidentProps>().props

  return (
    <OperatorLayout title={incident.identifier}>
      <Link href={operatorIncidentsPath()} className="text-muted-foreground hover:text-foreground mb-3 inline-block text-sm">
        All incidents
      </Link>
      <PageHeading
        title={
          <span className="flex items-baseline gap-3">
            <span className="font-mono">{incident.identifier}</span>
            <span>{incident.name}</span>
          </span>
        }
        lead="Everything Firefight did for this incident, in order: its alerts and routing, its events, each workflow step, webhook deliveries, failed calls to the chat platform, and Halon's runs."
      />
      <div className="mb-6 flex flex-wrap gap-2 text-xs">
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.active}`}>{incident.status}</span>
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>{incident.workspaceName}</span>
        {incident.problems > 0 && (
          <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.error}`}>{incident.problems} failed</span>
        )}
        <span className={`rounded-full border px-2.5 py-1 ${TONE_CLASSES.neutral}`}>
          {entries.length < total ? `first ${entries.length} of ${total} records` : `${total} records`}
        </span>
      </div>
      <Card className="px-6 pt-6 pb-1">
        {entries.length === 0 ? (
          <p className="text-muted-foreground pb-5 text-sm">Nothing recorded for this incident yet.</p>
        ) : (
          <ol className="list-none">
            {entries.map((entry, index) => (
              <ProcessEntryRow key={entry.key} entry={entry} last={index === entries.length - 1} />
            ))}
          </ol>
        )}
      </Card>
    </OperatorLayout>
  )
}
