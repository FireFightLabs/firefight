import { Deferred, Head, Link, usePage } from "@inertiajs/react"
import { IconArrowRight } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import {
  IncidentHeader,
  IncidentTimeline,
  IncidentActionsSidebar,
  IncidentPostmortemCard,
} from "@/modules/incidents/components"
import type { Incident, IncidentAction, TimelineEvent } from "@/modules/incidents/types"
import { dashboardPath } from "@/lib/routes"
import { Skeleton } from "@/components/ui/skeleton"

interface IncidentShowProps {
  incident: Incident
  timelineEvents?: TimelineEvent[]
  actions?: IncidentAction[]
  hasPostmortem: boolean
  postmortemStatus?: string
}

function TimelineSkeleton() {
  return (
    <div className="space-y-4">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="flex gap-3">
          <Skeleton className="size-8 rounded-full shrink-0" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-48" />
            <Skeleton className="h-3 w-64" />
          </div>
        </div>
      ))}
    </div>
  )
}

function ActionsSkeleton() {
  return (
    <div className="space-y-3">
      <Skeleton className="h-5 w-24" />
      <Skeleton className="h-2 w-full rounded-full" />
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center gap-2">
          <Skeleton className="size-4 shrink-0" />
          <Skeleton className="h-4 flex-1" />
        </div>
      ))}
    </div>
  )
}

export default function IncidentShow() {
  const { incident, timelineEvents, actions, hasPostmortem, postmortemStatus } = usePage<IncidentShowProps>().props

  return (
    <AuthenticatedLayout title={incident.identifier}>
      <Head title={`${incident.identifier} — ${incident.name}`} />
      <div className="mx-auto w-full max-w-6xl px-4 py-6 lg:px-6">
        <nav className="flex items-center gap-1.5 text-sm text-muted-foreground mb-6">
          <Link href={dashboardPath()} className="hover:text-foreground transition-colors">
            Incidents
          </Link>
          <IconArrowRight className="size-3 text-muted-foreground/40" />
          <span className="font-medium text-foreground">{incident.identifier}</span>
        </nav>

        <IncidentHeader incident={incident} />

        <div className="-mx-4 lg:-mx-6 mt-2 border-t bg-muted/30">
          <div className="mx-auto w-full max-w-6xl px-4 lg:px-6 py-6">
            <div className="flex flex-col lg:flex-row gap-6">
              <div className="flex-1 min-w-0">
                <Deferred data="timelineEvents" fallback={<TimelineSkeleton />}>
                  <div className="flex items-center gap-2 mb-5">
                    <div className="h-5 w-1 rounded-full bg-primary" />
                    <h2 className="text-base font-semibold">Timeline</h2>
                    <span className="rounded-full bg-muted px-2 py-0.5 text-[11px] font-medium tabular-nums text-muted-foreground">
                      {(timelineEvents ?? []).length}
                    </span>
                  </div>
                  <IncidentTimeline events={timelineEvents ?? []} />
                </Deferred>
              </div>

              <div className="w-full lg:w-[340px] shrink-0">
                <div className="lg:sticky lg:top-[calc(var(--header-height)+1.5rem)]">
                  <div className="mb-4">
                    <IncidentPostmortemCard incidentId={incident.id} hasPostmortem={hasPostmortem} postmortemStatus={postmortemStatus} />
                  </div>
                  <Deferred data="actions" fallback={<ActionsSkeleton />}>
                    <IncidentActionsSidebar actions={actions ?? []} />
                  </Deferred>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
