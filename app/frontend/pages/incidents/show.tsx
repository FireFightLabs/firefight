import { Head, Link } from "@inertiajs/react"
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

// -- Mock Data (will be replaced by backend props) --

const incident: Incident = {
  id: "1",
  identifier: "INC-042",
  name: "Payment processing failures in EU region",
  summary:
    "Multiple payment processing failures detected in the EU region affecting Stripe integration. Customers are unable to complete checkout. The issue appears related to a misconfigured rate limit on the payment gateway proxy deployed at 07:45 UTC.",
  status: { name: "Investigating", lifecycleStage: "active", color: "#3B82F6" },
  severity: { name: "Critical", rank: 4, color: "#DC143C" },
  type: { name: "Service Outage" },
  lead: { name: "Sarah Chen", initials: "SC" },
  declaredBy: { name: "Alex Kim" },
  declaredAt: "2026-03-25T08:15:00Z",
  detectedAt: "2026-03-25T07:58:00Z",
  resolvedAt: null,
  source: "slack",
  channelName: "inc-042-payment-eu-failures",
  isPrivate: false,
}

const timelineEvents: TimelineEvent[] = [
  { id: "t1", eventType: "incident.created", actor: "Alex Kim", createdAt: "2026-03-25T08:15:00Z", description: "created this incident" },
  { id: "t2", eventType: "lead.assigned", actor: "Alex Kim", createdAt: "2026-03-25T08:16:30Z", description: "assigned Sarah Chen as Incident Lead" },
  { id: "t3", eventType: "incident.updated", actor: "Sarah Chen", createdAt: "2026-03-25T08:25:00Z", description: "updated the incident", changes: [{ field: "severity", before: "Major", after: "Critical" }] },
  { id: "t4", eventType: "incident.escalated", actor: "Sarah Chen", createdAt: "2026-03-25T08:30:00Z", description: "escalated this incident", details: "Paging on-call platform engineer — payment failures affecting all EU customers" },
  { id: "t5", eventType: "action.created", actor: "Sarah Chen", createdAt: "2026-03-25T08:35:00Z", description: 'created action: "Check Stripe dashboard for error rates"' },
  { id: "t6", eventType: "action.created", actor: "Sarah Chen", createdAt: "2026-03-25T08:36:00Z", description: 'created action: "Review payment proxy rate limit config"' },
  { id: "t7", eventType: "incident.updated", actor: "James Wilson", createdAt: "2026-03-25T09:10:00Z", description: "posted a status update", details: "Root cause identified: rate limit on payment-proxy was set to 100 req/s instead of 10,000 req/s after the 07:45 deployment. Rolling back the config change now." },
  { id: "t8", eventType: "action.completed", actor: "James Wilson", createdAt: "2026-03-25T09:15:00Z", description: 'completed action: "Review payment proxy rate limit config"' },
  { id: "t9", eventType: "incident.updated", actor: "Sarah Chen", createdAt: "2026-03-25T09:30:00Z", description: "updated the incident", changes: [{ field: "status", before: "Investigating", after: "Monitoring" }], details: "Rate limit config rolled back. Payment success rate recovering. Monitoring for stability." },
  { id: "t10", eventType: "action.created", actor: "Sarah Chen", createdAt: "2026-03-25T09:35:00Z", description: 'created follow-up: "Add rate limit validation to CI pipeline"' },
]

const mockActions: IncidentAction[] = [
  { id: "a1", description: "Check Stripe dashboard for error rates", actionType: "action", status: "done", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a2", description: "Review payment proxy rate limit config", actionType: "action", status: "done", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a3", description: "Notify affected EU customers via status page", actionType: "action", status: "in_progress", assignee: "Maria Garcia", createdBy: "Sarah Chen" },
  { id: "a4", description: "Verify no payment data was lost during the outage", actionType: "action", status: "open", assignee: null, createdBy: "Sarah Chen" },
  { id: "a5", description: "Add rate limit validation to CI pipeline", actionType: "followup", status: "open", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a6", description: "Create runbook for payment proxy configuration changes", actionType: "followup", status: "open", assignee: null, createdBy: "Sarah Chen" },
]

// -- Page Component --

export default function IncidentShow() {
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

        {/* Visual break — full-bleed muted band for activity section */}
        <div className="-mx-4 lg:-mx-6 mt-2 border-t bg-muted/30">
          <div className="mx-auto w-full max-w-6xl px-4 lg:px-6 py-6">
            <div className="flex flex-col lg:flex-row gap-6">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-5">
                  <div className="h-5 w-1 rounded-full bg-primary" />
                  <h2 className="text-base font-semibold">Timeline</h2>
                  <span className="rounded-full bg-muted px-2 py-0.5 text-[11px] font-medium tabular-nums text-muted-foreground">
                    {timelineEvents.length}
                  </span>
                </div>
                <IncidentTimeline events={timelineEvents} />
              </div>

              <div className="w-full lg:w-[340px] shrink-0">
                <div className="lg:sticky lg:top-[calc(var(--header-height)+1.5rem)]">
                  <div className="mb-4">
                    <IncidentPostmortemCard incidentId={incident.id} hasPostmortem={true} />
                  </div>
                  <IncidentActionsSidebar actions={mockActions} />
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
