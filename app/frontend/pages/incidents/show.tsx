import { Deferred, Head, Link, usePage } from "@inertiajs/react"

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
    <div className="space-y-5">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="flex gap-4">
          <Skeleton className="size-[26px] rounded-full shrink-0" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-4 w-56" />
            <Skeleton className="h-3 w-72" />
          </div>
        </div>
      ))}
    </div>
  )
}

function ActionsSkeleton() {
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <Skeleton className="h-4 w-20" />
      <Skeleton className="h-1 w-full rounded-full" />
      {Array.from({ length: 3 }).map((_, i) => (
        <div key={i} className="flex items-center gap-2">
          <Skeleton className="size-4 shrink-0 rounded-full" />
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

      <div>
        <div className="mx-auto w-full max-w-6xl px-4 py-8 lg:px-8 lg:py-10">
          <nav className="mb-8 flex items-center gap-2 text-[12px] text-muted-foreground/80">
            <Link
              href={dashboardPath()}
              className="transition-colors hover:text-foreground"
            >
              Incidents
            </Link>
            <span className="text-muted-foreground/30">/</span>
            <span className="font-mono text-foreground/90">{incident.identifier}</span>
          </nav>

          <IncidentHeader incident={incident} />

          <div className="flex flex-col gap-8 lg:flex-row lg:gap-10">
            <div className="min-w-0 flex-1">
              <Deferred data="timelineEvents" fallback={<TimelineSkeleton />}>
                <div className="mb-6 flex items-baseline gap-3">
                  <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-foreground/90">
                    Timeline
                  </h2>
                  <span className="font-mono text-[11px] tabular-nums text-muted-foreground/70">
                    {(timelineEvents ?? []).length}
                  </span>
                  <div className="flex-1 h-px bg-border/50" />
                </div>
                <IncidentTimeline events={timelineEvents ?? []} />
              </Deferred>
            </div>

            <aside className="w-full shrink-0 lg:w-[336px]">
              <div className="lg:sticky lg:top-[calc(var(--header-height)+1.75rem)]">
                <div className="mb-3">
                  <IncidentPostmortemCard
                    incidentId={incident.id}
                    hasPostmortem={hasPostmortem}
                    postmortemStatus={postmortemStatus}
                  />
                </div>
                <Deferred data="actions" fallback={<ActionsSkeleton />}>
                  <IncidentActionsSidebar actions={actions ?? []} />
                </Deferred>
              </div>
            </aside>
          </div>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}

