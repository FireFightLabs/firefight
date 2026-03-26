import {
  IconAlertTriangle,
  IconArrowRight,
  IconCircleCheck,
  IconCirclePlus,
  IconCopy,
  IconFileText,
  IconFlame,
  IconHandGrab,
  IconLink,
  IconRefresh,
  IconUserCheck,
} from "@tabler/icons-react"

import type { TimelineEvent } from "@/modules/incidents/types"

const eventIcons: Record<string, typeof IconFlame> = {
  "incident.created": IconFlame,
  "incident.updated": IconRefresh,
  "incident.resolved": IconCircleCheck,
  "incident.reopened": IconAlertTriangle,
  "incident.escalated": IconAlertTriangle,
  "lead.assigned": IconUserCheck,
  "action.created": IconCirclePlus,
  "action.picked_up": IconHandGrab,
  "action.completed": IconCircleCheck,
  "postmortem.generated": IconFileText,
  "relationship.created": IconLink,
  "incident.marked_duplicate": IconCopy,
}

const eventDotColors: Record<string, string> = {
  "incident.created": "bg-primary text-primary-foreground ring-primary/20",
  "incident.updated": "bg-blue-500 text-white ring-blue-500/20",
  "incident.resolved": "bg-emerald-500 text-white ring-emerald-500/20",
  "incident.reopened": "bg-amber-500 text-white ring-amber-500/20",
  "incident.escalated": "bg-red-500 text-white ring-red-500/20",
  "lead.assigned": "bg-violet-500 text-white ring-violet-500/20",
  "action.created": "bg-muted text-muted-foreground ring-border",
  "action.picked_up": "bg-muted text-muted-foreground ring-border",
  "action.completed": "bg-emerald-500 text-white ring-emerald-500/20",
  "postmortem.generated": "bg-violet-500 text-white ring-violet-500/20",
  "relationship.created": "bg-muted text-muted-foreground ring-border",
  "incident.marked_duplicate": "bg-muted text-muted-foreground ring-border",
}

const isHighlightEvent = (type: string) =>
  [
    "incident.created",
    "incident.resolved",
    "incident.escalated",
    "incident.reopened",
  ].includes(type)

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleTimeString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
  })
}

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
  })
}

function ActorAvatar({ name }: { name: string }) {
  const initials = name
    .split(" ")
    .map((n) => n[0])
    .join("")
    .toUpperCase()
    .slice(0, 2)

  return (
    <span className="inline-flex size-5 shrink-0 items-center justify-center rounded-full bg-muted text-[10px] font-medium text-muted-foreground">
      {initials}
    </span>
  )
}

export function IncidentTimeline({ events }: { events: TimelineEvent[] }) {
  return (
    <div className="relative">
      {events.map((event, i) => {
        const Icon = eventIcons[event.eventType] || IconRefresh
        const dotColor =
          eventDotColors[event.eventType] ||
          "bg-muted text-muted-foreground ring-border"
        const eventDate = formatDate(event.createdAt)
        const prevDate = i > 0 ? formatDate(events[i - 1].createdAt) : null
        const showDate = eventDate !== prevDate
        const highlight = isHighlightEvent(event.eventType)
        const hasContent =
          (event.changes && event.changes.length > 0) || event.details

        return (
          <div key={event.id}>
            {showDate && (
              <div className="relative flex items-center gap-3 py-3">
                <div className="absolute left-[15px] top-0 bottom-0 w-px bg-border" />
                <div className="relative z-10 flex size-8 items-center justify-center">
                  <span className="rounded-full bg-background px-2 text-[11px] font-semibold uppercase tracking-widest text-muted-foreground">
                    {eventDate}
                  </span>
                </div>
              </div>
            )}
            <div className="group relative flex gap-4 pb-1">
              {/* Connector line */}
              {i < events.length - 1 && (
                <div className="absolute left-[15px] top-8 bottom-0 w-px bg-border" />
              )}

              {/* Dot */}
              <div className="relative z-10 flex shrink-0 pt-0.5">
                <div
                  className={`flex size-8 items-center justify-center rounded-full ring-4 ${dotColor}`}
                >
                  <Icon className="size-3.5" />
                </div>
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0 pb-6">
                <div
                  className={`rounded-lg ${hasContent || highlight ? "border bg-card p-3" : "py-1"}`}
                >
                  <div className="flex items-center gap-2 flex-wrap">
                    <ActorAvatar name={event.actor} />
                    <span className="text-sm font-medium">{event.actor}</span>
                    <span className="text-sm text-muted-foreground">
                      {event.description}
                    </span>
                    <span className="ml-auto shrink-0 text-[11px] font-mono tabular-nums text-muted-foreground/70">
                      {formatTime(event.createdAt)}
                    </span>
                  </div>

                  {event.changes && event.changes.length > 0 && (
                    <div className="mt-2 flex flex-col gap-1.5">
                      {event.changes.map((change) => (
                        <div
                          key={change.field}
                          className="flex items-center gap-2 text-xs"
                        >
                          <span className="rounded bg-muted px-1.5 py-0.5 font-medium capitalize text-muted-foreground">
                            {change.field}
                          </span>
                          <span className="text-muted-foreground/60 line-through">
                            {change.before}
                          </span>
                          <IconArrowRight className="size-3 text-muted-foreground/40" />
                          <span className="font-medium">{change.after}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {event.details && (
                    <p className="mt-2 text-sm leading-relaxed text-muted-foreground border-l-2 border-border pl-3">
                      {event.details}
                    </p>
                  )}
                </div>
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
