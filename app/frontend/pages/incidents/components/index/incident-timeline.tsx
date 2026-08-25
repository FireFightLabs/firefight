import { Link } from "@inertiajs/react"
import {
  IconAlertTriangle,
  IconArrowRight,
  IconBellCheck,
  IconBellRinging,
  IconBook,
  IconCircleCheck,
  IconCirclePlus,
  IconCircleX,
  IconCopy,
  IconExternalLink,
  IconFileText,
  IconFlame,
  IconGitMerge,
  IconHandGrab,
  IconLink,
  IconListCheck,
  IconPaperclip,
  IconPencil,
  IconPin,
  IconPinnedOff,
  IconUserCheck,
  IconUserX,
} from "@tabler/icons-react"

import type { TimelineEvent } from "@/pages/incidents/types"
import { PersonChip } from "@/pages/incidents/components/index/person-chip"
import { TimelineFileAttachment } from "@/pages/incidents/components/index/timeline-file-attachment"
import { revealAction } from "@/pages/incidents/lib/action-anchor"
import { actionStatusIcons, actionStatusLabels, actionStatusStyles } from "@/pages/incidents/lib/action-status"

type EventType = TimelineEvent["eventType"]

const eventIcons: Record<EventType, typeof IconFlame> = {
  "incident.created": IconFlame,
  "incident.updated": IconPencil,
  "incident.accepted": IconCircleCheck,
  "incident.resolved": IconCircleCheck,
  "incident.reopened": IconAlertTriangle,
  "incident.canceled": IconCircleX,
  "incident.escalated": IconBellRinging,
  "incident.escalation_acknowledged": IconBellCheck,
  "incident.escalation_nudged": IconBellRinging,
  "lead.assigned": IconUserCheck,
  "role.assigned": IconUserCheck,
  "role.unassigned": IconUserX,
  "action.created": IconCirclePlus,
  "action.picked_up": IconHandGrab,
  "action.completed": IconCircleCheck,
  "action.reassigned": IconUserCheck,
  "postmortem.generated": IconFileText,
  "postmortem.edited": IconFileText,
  "relationship.created": IconLink,
  "incident.marked_duplicate": IconCopy,
  "incident.merged_into": IconGitMerge,
  "message.pinned": IconPin,
  "message.unpinned": IconPinnedOff,
  "message.file_shared": IconPaperclip,
  "alert.attached": IconBellRinging,
  "alert.resolved": IconBellCheck,
  "runbook.attached": IconBook,
  "runbook.applied": IconListCheck,
}

type DotAccent = "primary" | "emerald" | "amber" | "rose" | "violet" | "neutral"

const eventAccent: Partial<Record<EventType, DotAccent>> = {
  "incident.created": "primary",
  "incident.resolved": "emerald",
  "incident.reopened": "amber",
  "incident.escalated": "rose",
  "incident.escalation_nudged": "rose",
  "incident.escalation_acknowledged": "emerald",
  "lead.assigned": "violet",
  "role.assigned": "violet",
  "role.unassigned": "neutral",
  "action.completed": "emerald",
  "alert.attached": "amber",
  "alert.resolved": "emerald",
}

const solidAccent: Record<DotAccent, string> = {
  primary: "border-primary/50 bg-primary/8 text-primary",
  emerald: "border-emerald-500/50 bg-emerald-500/8 text-emerald-600 dark:border-emerald-400/50 dark:bg-emerald-400/8 dark:text-emerald-400",
  amber: "border-amber-500/50 bg-amber-500/8 text-amber-600 dark:border-amber-400/50 dark:bg-amber-400/8 dark:text-amber-400",
  rose: "border-rose-500/50 bg-rose-500/8 text-rose-600 dark:border-rose-400/50 dark:bg-rose-400/8 dark:text-rose-400",
  violet: "border-violet-500/50 bg-violet-500/8 text-violet-600 dark:border-violet-400/50 dark:bg-violet-400/8 dark:text-violet-400",
  neutral: "border-border bg-card text-muted-foreground",
}

const highlightEvents: EventType[] = [
  "incident.created",
  "incident.resolved",
  "incident.escalated",
  "incident.reopened",
  "lead.assigned",
]

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  })
}

function EventDot({ event }: { event: TimelineEvent }) {
  const Icon = event.automated ? IconFlame : eventIcons[event.eventType]
  const accent: DotAccent = event.automated ? "neutral" : eventAccent[event.eventType] ?? "neutral"

  return (
    <div className={`flex size-[28px] items-center justify-center overflow-hidden rounded-full border ${solidAccent[accent]}`}>
      {event.actorAvatarUrl ? (
        <img src={event.actorAvatarUrl} alt="" className="size-full object-cover" />
      ) : (
        <Icon className="size-[13px]" strokeWidth={1.5} />
      )}
    </div>
  )
}

function EventSubject({ event }: { event: TimelineEvent }) {
  if (event.person) {
    return <PersonChip person={event.person} fallback="" />
  }
  if (!event.subject) {
    return null
  }
  if (event.subject.href) {
    return (
      <Link href={event.subject.href} className="font-medium text-foreground hover:underline">
        {event.subject.label}
      </Link>
    )
  }
  return <span className="font-medium text-foreground">{event.subject.label}</span>
}

function ChangeList({ changes }: { changes: NonNullable<TimelineEvent["changes"]> }) {
  return (
    <div className="flex flex-col gap-1.5">
      {changes.map((change) => (
        <div key={change.field} className="flex items-center gap-2 text-xs">
          <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs uppercase tracking-wider text-muted-foreground">
            {change.field}
          </span>
          <span className="text-muted-foreground/80 line-through decoration-muted-foreground/40">
            {change.before}
          </span>
          <IconArrowRight className="size-3 text-muted-foreground/60" />
          <span className="font-medium text-foreground">{change.after}</span>
        </div>
      ))}
    </div>
  )
}

function ActionCard({ action }: { action: NonNullable<TimelineEvent["action"]> }) {
  const StatusIcon = actionStatusIcons[action.status]
  const statusColor = actionStatusStyles[action.status]

  function reveal() {
    revealAction(action.id)
  }

  return (
    <button
      type="button"
      onClick={reveal}
      className="flex w-full flex-col gap-1.5 text-left transition-colors hover:text-foreground"
      title="Show this item in the sidebar"
    >
      <span className="text-sm leading-relaxed text-foreground">{action.description}</span>
      <span className="flex items-center gap-2 text-xs text-muted-foreground">
        <span className={`inline-flex items-center gap-1 ${statusColor}`}>
          <StatusIcon className="size-3.5" strokeWidth={1.75} />
          {actionStatusLabels[action.status]}
        </span>
        <span className="text-muted-foreground/50">·</span>
        <PersonChip person={action.assignee ?? undefined} fallback="Unassigned" />
      </span>
    </button>
  )
}

function PinCard({ pin, withDivider }: { pin: NonNullable<TimelineEvent["pin"]>; withDivider: boolean }) {
  return (
    <div className={withDivider ? "mt-2 border-t border-border pt-2" : ""}>
      {pin.text && (
        <blockquote className="border-l-2 border-border pl-3 text-sm leading-relaxed text-muted-foreground whitespace-pre-line">
          {pin.text}
        </blockquote>
      )}
      {pin.permalink && (
        <a
          href={pin.permalink}
          target="_blank"
          rel="noopener noreferrer"
          className={`inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground ${pin.text ? "mt-2" : ""}`}
        >
          <IconExternalLink className="size-3.5" />
          Open in Slack
        </a>
      )}
    </div>
  )
}

function EventCard({ event }: { event: TimelineEvent }) {
  const hasChanges = Boolean(event.changes && event.changes.length > 0)
  const hasAction = Boolean(event.action)
  const hasPin = Boolean(event.pin && (event.pin.text || event.pin.permalink))
  const hasDetails = Boolean(event.details)
  const hasFile = Boolean(event.file)

  if (!hasChanges && !hasAction && !hasPin && !hasDetails && !hasFile) {
    return null
  }

  return (
    <div className="ml-[44px] mt-2.5 rounded-lg border border-border bg-card px-3.5 py-2.5">
      {event.changes && hasChanges && <ChangeList changes={event.changes} />}
      {event.action && <ActionCard action={event.action} />}
      {event.pin && hasPin && <PinCard pin={event.pin} withDivider={hasChanges || hasAction} />}
      {event.details && (
        <p className={`text-sm leading-relaxed text-muted-foreground ${hasChanges || hasAction || hasPin ? "mt-2 border-t border-border pt-2" : ""}`}>
          {event.details}
        </p>
      )}
      {event.file && (
        <TimelineFileAttachment file={event.file} withDivider={hasChanges || hasAction || hasPin || hasDetails} />
      )}
    </div>
  )
}

export function IncidentTimeline({ events }: { events: TimelineEvent[] }) {
  return (
    <ol className="relative">
      {events.map((event, index) => {
        const eventDate = formatDate(event.createdAt)
        const prevDate = index > 0 ? formatDate(events[index - 1].createdAt) : null
        const showDate = eventDate !== prevDate
        const highlight = highlightEvents.includes(event.eventType)
        const isLast = index === events.length - 1

        return (
          <li key={event.id} className="relative">
            {showDate && (
              <div className="relative flex items-center py-6">
                <div aria-hidden className="absolute left-[14px] top-0 bottom-0 w-px bg-border" />
                <div aria-hidden className="relative z-10 ml-[7.5px] size-3.5 rounded-full border border-border bg-muted-foreground" />
                <span className="ml-3 text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                  {eventDate}
                </span>
              </div>
            )}

            <div className="relative pb-5">
              {!isLast && <div aria-hidden className="absolute left-[14px] top-7 bottom-0 w-px bg-border" />}

              <div className="flex items-center gap-4">
                <div className="relative z-10 shrink-0">
                  <EventDot event={event} />
                </div>

                <div className="flex flex-1 min-w-0 items-center gap-2 flex-wrap text-sm">
                  <span className={`font-medium ${highlight ? "text-foreground" : "text-foreground/95"}`}>
                    {event.actor}
                  </span>
                  <span className="text-muted-foreground">{event.description}</span>
                  <EventSubject event={event} />
                  <span className="ml-auto shrink-0 text-xs tabular-nums text-muted-foreground/80">
                    {formatTime(event.createdAt)}
                  </span>
                </div>
              </div>

              <EventCard event={event} />
            </div>
          </li>
        )
      })}
    </ol>
  )
}
