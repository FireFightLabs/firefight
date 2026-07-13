import {
  IconAlertTriangle,
  IconArrowRight,
  IconBellCheck,
  IconBellRinging,
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
  "alert.attached": IconBellRinging,
  "alert.resolved": IconBellCheck,
}

type DotAccent = "primary" | "emerald" | "amber" | "rose" | "violet" | "neutral"

const eventAccent: Record<string, DotAccent> = {
  "incident.created": "primary",
  "incident.resolved": "emerald",
  "incident.reopened": "amber",
  "incident.escalated": "rose",
  "lead.assigned": "violet",
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
              <div className="relative flex items-center py-6">
                <div
                  aria-hidden
                  className="absolute left-[14px] top-0 bottom-0 w-px bg-border"
                />
                <div
                  aria-hidden
                  className="relative z-10 ml-[7.5px] size-3.5 rounded-full border border-border bg-muted-foreground"
                />
                <span className="ml-3 text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                  {eventDate}
                </span>
              </div>
            )}

            <div className="relative pb-5">
              {!isLast && (
                <div
                  aria-hidden
                  className="absolute left-[14px] top-7 bottom-0 w-px bg-border"
                />
              )}

              <div className="flex items-center gap-4">
                <div className="relative z-10 shrink-0">
                  <div
                    className={`flex size-[28px] items-center justify-center overflow-hidden rounded-full border ${dotClasses}`}
                  >
                    {event.actorAvatarUrl ? (
                      <img
                        src={event.actorAvatarUrl}
                        alt=""
                        className="size-full object-cover"
                      />
                    ) : (
                      <Icon className="size-[13px]" strokeWidth={1.5} />
                    )}
                  </div>
                </div>

                <div className="flex flex-1 min-w-0 items-center gap-2 flex-wrap text-sm">
                  <span className={`font-medium ${highlight ? "text-foreground" : "text-foreground/95"}`}>
                    {event.actor}
                  </span>
                  <span className="text-muted-foreground">{event.description}</span>
                  <span className="ml-auto shrink-0 text-xs tabular-nums text-muted-foreground/80">
                    {formatTime(event.createdAt)}
                  </span>
                </div>
              </div>

              {hasContent && (
                <div className="ml-[44px] mt-2.5 rounded-lg border border-border bg-card px-3.5 py-2.5">
                  {event.changes && event.changes.length > 0 && (
                    <div className="flex flex-col gap-1.5">
                      {event.changes.map((change) => (
                        <div
                          key={change.field}
                          className="flex items-center gap-2 text-xs"
                        >
                          <span className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs uppercase tracking-wider text-muted-foreground">
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
                      className={`text-sm leading-relaxed text-muted-foreground ${event.changes && event.changes.length > 0 ? "mt-2 pt-2 border-t border-border" : ""}`}
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
          </li>
        )
      })}
    </ol>
  )
}
