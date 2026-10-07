import { Deferred, Head, Link, router, usePage } from "@inertiajs/react";

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout";
import { ActionsSkeleton } from "@/pages/incidents/components/index/actions-skeleton";
import { AlertsPanel } from "@/pages/incidents/components/index/alerts-panel";
import { IncidentHeader } from "@/pages/incidents/components/index/incident-header";
import { TestIncidentBanner } from "@/pages/incidents/components/index/test-incident-banner";
import { IncidentTimeline } from "@/pages/incidents/components/index/incident-timeline";
import { InvestigationSheet } from "@/components/investigations/investigation-sheet";
import { IncidentActionsSidebar } from "@/pages/incidents/components/index/incident-actions-sidebar";
import { IncidentPostmortemCard } from "@/pages/incidents/components/index/incident-postmortem-card";
import { RolesPanel } from "@/pages/incidents/components/index/roles-panel";
import { SubscribersPanel } from "@/pages/incidents/components/index/subscribers-panel";
import { RunbooksPanel } from "@/pages/incidents/components/index/runbooks-panel";
import { TimelineSkeleton } from "@/pages/incidents/components/index/timeline-skeleton";
import type { IncidentPageProps } from "@/pages/incidents/types";
import { useCan } from "@/lib/permissions";
import { dashboardPath, incidentPath } from "@/lib/routes";
import { INVESTIGATION_START_PROP, OPEN_INVESTIGATION_PROP } from "@/lib/generated/constants";

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
    subscribed,
    openInvestigation,
    investigationStart,
  } = usePage<IncidentPageProps>().props;
  const canEditIncident = useCan("incidents");

  // Closing a run drops it from the address and loads nothing else but the Investigate button, which the run may have freed.
  function closeInvestigation() {
    router.get(incidentPath(incident.id), {}, { only: [OPEN_INVESTIGATION_PROP, INVESTIGATION_START_PROP], preserveScroll: true, preserveState: true, replace: true });
  }
  const rolesBlockedReason = canEditIncident
    ? incident.changeBlockedReason
    : "You do not have permission to change incidents.";

  return (
    <AuthenticatedLayout title={incident.name}>
      <Head title={`${incident.identifier} — ${incident.name}`} />

      <div className="mx-auto w-full max-w-6xl px-6 py-4 md:py-6 lg:px-10">
        <nav className="mb-8 flex items-center gap-2 text-[12px] text-fg-muted">
          <Link
            href={dashboardPath()}
            className="transition-colors hover:text-fg-primary"
          >
            Incidents
          </Link>
          <span className="text-fg-disabled">/</span>
          <span className="font-mono text-fg-body">
            {incident.identifier}
          </span>
        </nav>

        {incident.onboardingWalkthrough && <TestIncidentBanner channelUrl={channelUrl} />}

        <IncidentHeader
          incident={incident}
          channelUrl={channelUrl}
          linkable={linkableIncidents}
          canEdit={canEditIncident}
          members={memberChoices}
          investigationStart={investigationStart}
        />

        <div className="flex flex-col gap-8 lg:flex-row lg:gap-10">
          <div className="min-w-0 flex-1">
            <Deferred data="timelineEvents" fallback={<TimelineSkeleton />}>
              <div className="mb-2 flex items-baseline gap-3">
                <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-fg-body">
                  Timeline
                </h2>
                <span className="text-[11px] tabular-nums text-fg-muted">
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
              <SubscribersPanel
                subscribers={incident.subscribers}
                subscribed={subscribed}
                incidentId={incident.id}
              />
              <Deferred data="actions" fallback={<ActionsSkeleton />}>
                <IncidentActionsSidebar
                  actions={actions ?? []}
                  actionBlockedReason={incident.actionBlockedReason}
                  followupBlockedReason={incident.followupBlockedReason}
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
                claimBlockedReason={incident.actionBlockedReason}
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
      <InvestigationSheet investigation={openInvestigation} prop={OPEN_INVESTIGATION_PROP} onClose={closeInvestigation} />
    </AuthenticatedLayout>
  );
}
