import { Deferred, Head, Link, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ActionsSkeleton } from "@/pages/incidents/components/index/actions-skeleton"
import { IncidentHeader } from "@/pages/incidents/components/index/incident-header"
import { IncidentTimeline } from "@/pages/incidents/components/index/incident-timeline"
import { IncidentActionsSidebar } from "@/pages/incidents/components/index/incident-actions-sidebar"
import { IncidentPostmortemCard } from "@/pages/incidents/components/index/incident-postmortem-card"
import { TimelineSkeleton } from "@/pages/incidents/components/index/timeline-skeleton"
import type { Incident, IncidentAction, TimelineEvent } from "@/pages/incidents/types"
import type { SharedProps } from "@/types"
import { dashboardPath } from "@/lib/routes"

interface IncidentPageProps extends SharedProps {
  incident: Incident
  timelineEvents?: TimelineEvent[]
  actions?: IncidentAction[]
  hasPostmortem: boolean
  postmortemStatus?: string
}

export default function IncidentPage() {
  const { incident, timelineEvents, actions, hasPostmortem, postmortemStatus } = usePage<IncidentPageProps>().props
  const canAddAction = ["triage", "active"].includes(incident.status.lifecycleStage)
  const canAddFollowup = ["closed", "canceled"].includes(incident.status.lifecycleStage)

  return (
    <AuthenticatedLayout title={incident.identifier}>
      <Head title={`${incident.identifier} — ${incident.name}`} />

      <div className="mx-auto w-full max-w-6xl px-6 py-4 md:py-6 lg:px-10">
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
              <div className="mb-2 flex items-baseline gap-3">
                <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-foreground/90">
                  Timeline
                </h2>
                <span className="text-[11px] tabular-nums text-muted-foreground/70">
                  {(timelineEvents ?? []).length}
                </span>
              </div>
              <IncidentTimeline events={timelineEvents ?? []} />
            </Deferred>
          </div>

          <aside className="w-full shrink-0 lg:w-[336px]">
            <div className="lg:sticky lg:top-[calc(var(--header-height)+1.75rem)]">
              <Deferred data="actions" fallback={<ActionsSkeleton />}>
                <IncidentActionsSidebar actions={actions ?? []} canAddAction={canAddAction} canAddFollowup={canAddFollowup} incidentId={incident.id} />
              </Deferred>
              <div className="mt-3">
                <IncidentPostmortemCard
                  incidentId={incident.id}
                  hasPostmortem={hasPostmortem}
                  postmortemStatus={postmortemStatus}
                  incidentLifecycleStage={incident.status.lifecycleStage}
                />
              </div>
            </div>
          </aside>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
