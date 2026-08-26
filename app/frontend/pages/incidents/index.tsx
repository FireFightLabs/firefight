import { Deferred, Head, Link, usePage } from "@inertiajs/react";

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout";
import { ActionsSkeleton } from "@/pages/incidents/components/index/actions-skeleton";
import { AlertsPanel } from "@/pages/incidents/components/index/alerts-panel";
import { IncidentHeader } from "@/pages/incidents/components/index/incident-header";
import { IncidentTimeline } from "@/pages/incidents/components/index/incident-timeline";
import { IncidentActionsSidebar } from "@/pages/incidents/components/index/incident-actions-sidebar";
import { IncidentPostmortemCard } from "@/pages/incidents/components/index/incident-postmortem-card";
import { RolesPanel } from "@/pages/incidents/components/index/roles-panel";
import { RunbooksPanel } from "@/pages/incidents/components/index/runbooks-panel";
import { TimelineSkeleton } from "@/pages/incidents/components/index/timeline-skeleton";
import type { AttachableRunbook } from "@/pages/incidents/components/index/attach-runbook-dialog";
import type { LinkableIncident } from "@/pages/incidents/components/index/link-incident-dialog";
import type {
  Incident,
  IncidentAction,
  TimelineEvent,
} from "@/pages/incidents/types";
import type { SharedProps } from "@/types";
import { useCan } from "@/lib/permissions";
import { dashboardPath } from "@/lib/routes";

interface IncidentPageProps extends SharedProps {
  incident: Incident;
  timelineEvents?: TimelineEvent[];
  actions?: IncidentAction[];
  hasPostmortem: boolean;
  postmortemStatus?: string;
  postmortemGenerationState?: "generating" | "failed";
  attachableRunbooks: AttachableRunbook[];
  channelUrl?: string | null;
  linkableIncidents: LinkableIncident[];
  memberChoices: { value: string; label: string }[];
}

export default function IncidentPage() {
  const {
    incident,
    timelineEvents,
    actions,
    hasPostmortem,
    postmortemStatus,
    postmortemGenerationState,
    attachableRunbooks,
    channelUrl,
    linkableIncidents,
    memberChoices,
  } = usePage<IncidentPageProps>().props;
  const canAddAction = ["triage", "active"].includes(
    incident.status.lifecycleStage,
  );
  const canAddFollowup = ["closed", "canceled"].includes(
    incident.status.lifecycleStage,
  );
  const canEditIncident = useCan("incidents");
  const rolesBlockedReason = canEditIncident
    ? incident.changeBlockedReason
    : "You do not have permission to change incidents.";

  return (
    <AuthenticatedLayout title={incident.name}>
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
          <span className="font-mono text-foreground/90">
            {incident.identifier}
          </span>
        </nav>

        <IncidentHeader
          incident={incident}
          channelUrl={channelUrl}
          linkable={linkableIncidents}
          canEdit={canEditIncident}
          leadCandidates={memberChoices}
        />

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
              <IncidentTimeline
                events={timelineEvents ?? []}
                incidentId={incident.id}
                canDismiss={canEditIncident}
              />
            </Deferred>
          </div>

          <aside className="w-full shrink-0 lg:w-[336px]">
            {/* Gap rather than margins on each card, so a panel that renders
                nothing leaves no space behind it. */}
            <div className="flex flex-col gap-3 lg:sticky lg:top-[calc(var(--header-height)+1.75rem)]">
              <RolesPanel
                roles={incident.roles}
                incidentId={incident.id}
                candidates={memberChoices}
                blockedReason={rolesBlockedReason}
              />
              <Deferred data="actions" fallback={<ActionsSkeleton />}>
                <IncidentActionsSidebar
                  actions={actions ?? []}
                  canAddAction={canAddAction}
                  canAddFollowup={canAddFollowup}
                  incidentId={incident.id}
                  candidates={memberChoices}
                  canEdit={canEditIncident}
                />
              </Deferred>
              <AlertsPanel alerts={incident.alerts} />
              <RunbooksPanel
                runbooks={incident.runbooks}
                attachable={attachableRunbooks}
                incidentId={incident.id}
                canEdit={canEditIncident}
              />
              <IncidentPostmortemCard
                incidentId={incident.id}
                hasPostmortem={hasPostmortem}
                postmortemStatus={postmortemStatus}
                postmortemGenerationState={postmortemGenerationState}
                incidentLifecycleStage={incident.status.lifecycleStage}
              />
            </div>
          </aside>
        </div>
      </div>
    </AuthenticatedLayout>
  );
}
