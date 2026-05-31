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
  IconPaperclip,
  IconRefresh,
  IconUserCheck,
} from "@tabler/icons-react"

import type { TimelineEvent } from "@/pages/incidents/types"
import { ActorAvatar } from "@/pages/incidents/components/index/actor-avatar"
import { TimelineFileAttachment } from "@/pages/incidents/components/index/timeline-file-attachment"

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
  "postmortem.edited": IconFileText,
  "relationship.created": IconLink,
  "incident.marked_duplicate": IconCopy,
  "message.file_shared": IconPaperclip,
}

type DotAccent = "primary" | "emerald" | "amber" | "rose" | "violet" | "neutral"

const eventAccent: Record<string, DotAccent> = {
  "incident.created": "primary",
  "incident.updated": "primary",
  "incident.resolved": "emerald",
  "incident.reopened": "amber",
  "incident.escalated": "rose",
  "lead.assigned": "violet",
  "action.completed": "emerald",
  "postmortem.generated": "violet",
  "postmortem.edited": "violet",
  "message.file_shared": "primary",
}

const solidAccent: Record<DotAccent, string> = {
  primary: "border-primary/60 bg-primary/20 text-primary",
  emerald: "border-emerald-400/60 bg-emerald-400/15 text-emerald-300",
  amber: "border-amber-400/60 bg-amber-400/15 text-amber-300",
  rose: "border-rose-400/60 bg-rose-400/15 text-rose-300",
  violet: "border-violet-400/60 bg-violet-400/15 text-violet-300",
  neutral: "border-border bg-card text-muted-foreground",
}

const isHighlightEvent = (type: string) =>
  [
    "incident.created",
    "incident.resolved",
    "incident.escalated",
    "incident.reopened",
    "lead.assigned",
  ].includes(type)

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

export function IncidentTimeline({ events }: { events: TimelineEvent[] }) {
  return (
    <ol className="relative">
      {events.map((event, i) => {
        const Icon = eventIcons[event.eventType] || IconRefresh
        const accent: DotAccent = eventAccent[event.eventType] ?? "neutral"
        const dotClasses = solidAccent[accent]
        const eventDate = formatDate(event.createdAt)
        const prevDate = i > 0 ? formatDate(events[i - 1].createdAt) : null
        const showDate = eventDate !== prevDate
        const highlight = isHighlightEvent(event.eventType)
        const hasContent =
          (event.changes && event.changes.length > 0) || Boolean(event.details) || Boolean(event.file)
        const isLast = i === events.length - 1

        return (
          <li key={event.id} className="relative">
            {showDate && (
              <div className="relative flex items-center py-3 pl-14">
                <div
                  aria-hidden
                  className="absolute left-[13px] top-0 bottom-0 w-px bg-border"
                />
                <span className="relative z-10 -ml-14 inline-flex items-center gap-2 rounded-full bg-background px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.2em] text-muted-foreground">
                  <span aria-hidden className="size-1 rounded-full bg-muted-foreground/60" />
                  {eventDate}
                </span>
              </div>
            )}

            <div className="relative flex gap-4 pb-5">
              {!isLast && (
                <div
                  aria-hidden
                  className="absolute left-[13px] top-7 bottom-0 w-px bg-border"
                />
              )}

              <div className="relative z-10 shrink-0 pt-0.5">
                <div
                  className={`flex size-[26px] items-center justify-center rounded-full border ${dotClasses}`}
                >
                  <Icon className="size-[13px]" strokeWidth={2} />
                </div>
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap text-[13px]">
                  <ActorAvatar name={event.actor} />
                  <span className={`font-medium ${highlight ? "text-foreground" : "text-foreground/95"}`}>
                    {event.actor}
                  </span>
                  <span className="text-muted-foreground">{event.description}</span>
                  <span className="ml-auto shrink-0 font-mono text-[11px] tabular-nums text-muted-foreground/80">
                    {formatTime(event.createdAt)}
                  </span>
                </div>

                {hasContent && (
                  <div className="mt-2.5 rounded-lg border border-border bg-card px-3.5 py-2.5">
                    {event.changes && event.changes.length > 0 && (
                      <div className="flex flex-col gap-1.5">
                        {event.changes.map((change) => (
                          <div
                            key={change.field}
                            className="flex items-center gap-2 text-[12px]"
                          >
                            <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-[10.5px] uppercase tracking-wider text-muted-foreground">
                              {change.field}
                            </span>
                            <span className="text-muted-foreground/80 line-through decoration-muted-foreground/40">
                              {change.before}
                            </span>
                            <IconArrowRight className="size-3 text-muted-foreground/60" />
                            <span className="font-medium text-foreground">
                              {change.after}
                            </span>
                          </div>
                        ))}
                      </div>
                    )}

                    {event.details && (
                      <p
                        className={`text-[13px] leading-[1.6] text-muted-foreground ${event.changes && event.changes.length > 0 ? "mt-2 pt-2 border-t border-border" : ""}`}
                      >
                        {event.details}
                      </p>
                    )}

                    {event.file && (
                      <TimelineFileAttachment
                        file={event.file}
                        withDivider={Boolean((event.changes && event.changes.length > 0) || event.details)}
                      />
                    )}
                  </div>
                )}
              </div>
            </div>
          </li>
        )
      })}
    </ol>
  )
}
