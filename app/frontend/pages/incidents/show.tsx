import { Head, Link } from "@inertiajs/react"
import {
  IconArrowLeft,
  IconArrowRight,
  IconBrandSlack,
  IconCheckbox,
  IconChecks,
  IconCircleCheck,
  IconCircleDashed,
  IconClock,
  IconDotsVertical,
  IconExternalLink,
  IconFileText,
  IconFlame,
  IconLoader,
  IconPlus,
  IconPointFilled,
  IconUser,
} from "@tabler/icons-react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import {
  IncidentTimeline,
  type TimelineEvent,
} from "@/components/incident-timeline"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import { dashboardPath, incidentPostmortemPath } from "@/lib/routes"

// -- Mock Data --

const incident = {
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

interface IncidentAction {
  id: string
  description: string
  actionType: "action" | "followup"
  status: "open" | "in_progress" | "done"
  assignee: string | null
  createdBy: string
}

const mockActions: IncidentAction[] = [
  { id: "a1", description: "Check Stripe dashboard for error rates", actionType: "action", status: "done", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a2", description: "Review payment proxy rate limit config", actionType: "action", status: "done", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a3", description: "Notify affected EU customers via status page", actionType: "action", status: "in_progress", assignee: "Maria Garcia", createdBy: "Sarah Chen" },
  { id: "a4", description: "Verify no payment data was lost during the outage", actionType: "action", status: "open", assignee: null, createdBy: "Sarah Chen" },
  { id: "a5", description: "Add rate limit validation to CI pipeline", actionType: "followup", status: "open", assignee: "James Wilson", createdBy: "Sarah Chen" },
  { id: "a6", description: "Create runbook for payment proxy configuration changes", actionType: "followup", status: "open", assignee: null, createdBy: "Sarah Chen" },
]

// -- Helpers --

const statusIcons: Record<string, typeof IconCircleDashed> = {
  open: IconCircleDashed,
  in_progress: IconLoader,
  done: IconCircleCheck,
}

const statusStyles: Record<string, string> = {
  open: "text-muted-foreground",
  in_progress: "text-amber-500",
  done: "text-emerald-500",
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  })
}

function formatDuration(start: string, end: string | null): string {
  const s = new Date(start)
  const e = end ? new Date(end) : new Date()
  const mins = Math.floor((e.getTime() - s.getTime()) / 60000)
  if (mins < 60) return `${mins}m`
  const hours = Math.floor(mins / 60)
  const rem = mins % 60
  if (hours < 24) return `${hours}h ${rem}m`
  const days = Math.floor(hours / 24)
  return `${days}d ${hours % 24}h`
}

function ActionItem({ action }: { action: IncidentAction }) {
  const StatusIcon = statusIcons[action.status]
  const statusColor = statusStyles[action.status]
  const isDone = action.status === "done"

  return (
    <div className="group flex items-start gap-3 rounded-md px-3 py-3 transition-colors hover:bg-muted/40 -mx-3">
      <div className={`mt-0.5 ${statusColor}`}>
        <StatusIcon className="size-[18px]" />
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-sm leading-snug ${isDone ? "line-through text-muted-foreground" : ""}`}>
          {action.description}
        </p>
        {action.assignee ? (
          <span className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground">
            <IconUser className="size-3" />
            {action.assignee}
          </span>
        ) : (
          <span className="mt-1 inline-flex items-center gap-1 text-xs text-muted-foreground/50 italic">
            Unassigned
          </span>
        )}
      </div>
      <Badge
        variant="outline"
        className={`text-[11px] capitalize shrink-0 ${statusColor} opacity-80`}
      >
        {action.status.replace("_", " ")}
      </Badge>
    </div>
  )
}

function ProgressBar({ done, total }: { done: number; total: number }) {
  const pct = total > 0 ? (done / total) * 100 : 0
  return (
    <div className="flex items-center gap-2">
      <div className="h-1.5 flex-1 rounded-full bg-muted overflow-hidden">
        <div
          className="h-full rounded-full bg-emerald-500 transition-all duration-500"
          style={{ width: `${pct}%` }}
        />
      </div>
      <span className="text-[11px] font-mono tabular-nums text-muted-foreground">
        {done}/{total}
      </span>
    </div>
  )
}

// -- Main Page --

export default function IncidentShow() {
  const actions = mockActions.filter((a) => a.actionType === "action")
  const followups = mockActions.filter((a) => a.actionType === "followup")
  const hasPostmortem = true
  const isActive = incident.status.lifecycleStage === "active"

  return (
    <AuthenticatedLayout title={incident.identifier}>
      <Head title={`${incident.identifier} — ${incident.name}`} />
      <div className="mx-auto w-full max-w-4xl px-4 py-6 lg:px-6">
        {/* Breadcrumb */}
        <nav className="flex items-center gap-1.5 text-sm text-muted-foreground mb-6">
          <Link
            href={dashboardPath()}
            className="hover:text-foreground transition-colors"
          >
            Incidents
          </Link>
          <IconArrowRight className="size-3 text-muted-foreground/40" />
          <span className="font-medium text-foreground">{incident.identifier}</span>
        </nav>

        {/* ===== HEADER ===== */}
        <header className="mb-8">
          {/* Badges row */}
          <div className="flex items-center gap-2 mb-3 flex-wrap">
            {isActive && (
              <span className="relative flex size-2.5">
                <span
                  className="absolute inline-flex size-full animate-ping rounded-full opacity-75"
                  style={{ backgroundColor: incident.status.color }}
                />
                <span
                  className="relative inline-flex size-2.5 rounded-full"
                  style={{ backgroundColor: incident.status.color }}
                />
              </span>
            )}
            <Badge
              variant="secondary"
              className="gap-1 font-medium"
              style={{
                backgroundColor: `${incident.severity.color}15`,
                color: incident.severity.color,
                borderColor: `${incident.severity.color}30`,
              }}
            >
              {incident.severity.name}
            </Badge>
            <Badge
              variant="secondary"
              className="gap-1"
              style={{
                backgroundColor: `${incident.status.color}15`,
                color: incident.status.color,
                borderColor: `${incident.status.color}30`,
              }}
            >
              {incident.status.name}
            </Badge>
            {incident.type && (
              <Badge variant="outline" className="text-xs text-muted-foreground">
                {incident.type.name}
              </Badge>
            )}
            <div className="ml-auto flex items-center gap-2">
              {incident.source === "slack" && (
                <Button variant="outline" size="sm" className="gap-1.5 text-muted-foreground">
                  <IconBrandSlack className="size-3.5" />
                  #{incident.channelName}
                  <IconExternalLink className="size-3" />
                </Button>
              )}
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="outline" size="icon" className="size-8">
                    <IconDotsVertical className="size-4" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem>Edit Incident</DropdownMenuItem>
                  <DropdownMenuItem>Change Status</DropdownMenuItem>
                  <DropdownMenuItem>Assign Lead</DropdownMenuItem>
                  <DropdownMenuSeparator />
                  <DropdownMenuItem>Close Incident</DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </div>

          {/* Title */}
          <h1 className="text-2xl font-bold tracking-tight mb-3">
            {incident.name}
          </h1>

          {/* Summary */}
          {incident.summary && (
            <p className="text-[15px] text-muted-foreground leading-relaxed mb-4">
              {incident.summary}
            </p>
          )}

          {/* Metadata grid */}
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-lg border bg-card/50 px-3 py-2.5">
              <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
                Lead
              </span>
              <div className="mt-1 flex items-center gap-2">
                <Avatar className="size-5">
                  <AvatarFallback className="text-[10px] font-medium">
                    {incident.lead?.initials ?? "?"}
                  </AvatarFallback>
                </Avatar>
                <span className="text-sm font-medium truncate">
                  {incident.lead?.name ?? "Unassigned"}
                </span>
              </div>
            </div>
            <div className="rounded-lg border bg-card/50 px-3 py-2.5">
              <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
                Declared
              </span>
              <div className="mt-1 flex items-center gap-1.5">
                <IconClock className="size-3.5 text-muted-foreground" />
                <span className="text-sm font-medium tabular-nums">
                  {new Date(incident.declaredAt).toLocaleTimeString("en-US", {
                    hour: "2-digit",
                    minute: "2-digit",
                  })}
                </span>
                <span className="text-xs text-muted-foreground">
                  {new Date(incident.declaredAt).toLocaleDateString("en-US", {
                    month: "short",
                    day: "numeric",
                  })}
                </span>
              </div>
            </div>
            <div className="rounded-lg border bg-card/50 px-3 py-2.5">
              <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
                Duration
              </span>
              <div className="mt-1">
                <span className="text-sm font-semibold font-mono tabular-nums">
                  {formatDuration(incident.declaredAt, incident.resolvedAt)}
                </span>
              </div>
            </div>
            <div className="rounded-lg border bg-card/50 px-3 py-2.5">
              <span className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">
                Identifier
              </span>
              <div className="mt-1">
                <span className="text-sm font-mono font-semibold">
                  {incident.identifier}
                </span>
              </div>
            </div>
          </div>
        </header>

        {/* ===== TIMELINE ===== */}
        <section className="mb-10">
          <div className="flex items-center gap-2 mb-5">
            <h2 className="text-base font-semibold">Timeline</h2>
            <span className="text-xs text-muted-foreground">
              {timelineEvents.length} events
            </span>
          </div>
          <IncidentTimeline events={timelineEvents} />
        </section>

        <Separator className="mb-8" />

        {/* ===== ACTIONS ===== */}
        <section className="mb-10">
          <div className="flex items-center justify-between mb-5">
            <div className="flex items-center gap-2">
              <h2 className="text-base font-semibold">Action Items</h2>
              <span className="text-xs text-muted-foreground">
                {mockActions.filter((a) => a.status === "done").length} of {mockActions.length} completed
              </span>
            </div>
            <Dialog>
              <DialogTrigger asChild>
                <Button variant="outline" size="sm">
                  <IconPlus className="size-4" />
                  Add
                </Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Add Action Item</DialogTitle>
                  <DialogDescription>
                    Create a new action or follow-up item for this incident.
                  </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-4 py-2">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="action-desc">Description</Label>
                    <Textarea id="action-desc" placeholder="What needs to be done?" rows={2} />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="action-assignee">Assignee</Label>
                    <Input id="action-assignee" placeholder="e.g. Sarah Chen" />
                  </div>
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancel</Button>
                  </DialogClose>
                  <Button>Create</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            {/* Actions card */}
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center gap-2">
                  <IconCheckbox className="size-4 text-muted-foreground" />
                  <CardTitle className="text-sm">Actions</CardTitle>
                </div>
                <div className="mt-2">
                  <ProgressBar
                    done={actions.filter((a) => a.status === "done").length}
                    total={actions.length}
                  />
                </div>
              </CardHeader>
              <CardContent className="pt-0">
                {actions.map((action) => (
                  <ActionItem key={action.id} action={action} />
                ))}
              </CardContent>
            </Card>

            {/* Follow-ups card */}
            <Card>
              <CardHeader className="pb-3">
                <div className="flex items-center gap-2">
                  <IconChecks className="size-4 text-muted-foreground" />
                  <CardTitle className="text-sm">Follow-ups</CardTitle>
                </div>
                <div className="mt-2">
                  <ProgressBar
                    done={followups.filter((a) => a.status === "done").length}
                    total={followups.length}
                  />
                </div>
              </CardHeader>
              <CardContent className="pt-0">
                {followups.map((action) => (
                  <ActionItem key={action.id} action={action} />
                ))}
              </CardContent>
            </Card>
          </div>
        </section>

        <Separator className="mb-8" />

        {/* ===== POSTMORTEM ===== */}
        <section className="mb-10">
          {hasPostmortem ? (
            <Link href={incidentPostmortemPath(incident.id)}>
              <Card className="group cursor-pointer border-primary/20 bg-gradient-to-r from-primary/[0.03] to-transparent transition-all hover:border-primary/40 hover:shadow-sm">
                <CardContent className="flex items-center gap-4 py-5">
                  <div className="flex size-10 items-center justify-center rounded-lg bg-primary/10">
                    <IconFileText className="size-5 text-primary" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold">Postmortem</span>
                      <Badge
                        variant="secondary"
                        className="text-[11px] bg-amber-500/15 text-amber-600 dark:text-amber-400"
                      >
                        In progress
                      </Badge>
                    </div>
                    <p className="mt-0.5 text-sm text-muted-foreground truncate">
                      Root cause analysis and action items for payment processing failures
                    </p>
                  </div>
                  <IconArrowRight className="size-4 text-muted-foreground/40 transition-transform group-hover:translate-x-0.5 group-hover:text-primary" />
                </CardContent>
              </Card>
            </Link>
          ) : (
            <Card className="border-dashed">
              <CardContent className="flex flex-col items-center justify-center py-12 gap-4">
                <div className="flex size-12 items-center justify-center rounded-full bg-muted">
                  <IconFileText className="size-6 text-muted-foreground" />
                </div>
                <div className="text-center">
                  <p className="text-sm font-semibold">No postmortem yet</p>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Generate a postmortem to document what happened and prevent recurrence.
                  </p>
                </div>
                <Button size="sm">
                  <IconFlame className="size-4" />
                  Generate Postmortem
                </Button>
              </CardContent>
            </Card>
          )}
        </section>
      </div>
    </AuthenticatedLayout>
  )
}
