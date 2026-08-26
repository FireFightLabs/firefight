import { useState } from "react"
import { Link } from "@inertiajs/react"
import {
  IconAlertTriangle,
  IconArrowRight,
  IconBellCheck,
  IconBellRinging,
  IconBook,
  IconChevronDown,
  IconChevronRight,
  IconCircleCheck,
  IconCirclePlus,
  IconCircleX,
  IconCopy,
  IconExternalLink,
  IconFileText,
  IconFlame,
  IconGitMerge,
  IconHandGrab,
  IconKey,
  IconLink,
  IconListCheck,
  IconPaperclip,
  IconPencil,
  IconPin,
  IconPinnedOff,
  IconRobot,
  IconSparkles,
  IconUserCheck,
  IconUserX,
  type Icon,
} from "@tabler/icons-react"

import type { ActorCompact } from "@/types/serializers"
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
import type { TimelineEvent } from "@/pages/incidents/types"
import { ActorChip } from "@/pages/incidents/components/index/actor-chip"
import { PRINCIPAL_KINDS } from "@/lib/generated/constants"
import {
  DismissNoteAction,
  NoteQuote,
  noteAccent,
} from "@/pages/incidents/components/index/timeline-note"
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
  "milestone.noted": IconSparkles,
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

function dotAccent(event: TimelineEvent): DotAccent {
  if (event.milestone) {
    return noteAccent[event.milestone.kind]
  }
  if (event.automated) {
    return "neutral"
  }
  return eventAccent[event.eventType] ?? "neutral"
}

// A machine's row wears its own mark instead of the event's, since who acted
// is the thing a reader needs first.
const MACHINE_ICONS: Partial<Record<ActorCompact["kind"], Icon>> = {
  [PRINCIPAL_KINDS.AGENT]: IconRobot,
  [PRINCIPAL_KINDS.API_KEY]: IconKey,
}

function eventIcon(event: TimelineEvent) {
  const machineIcon = event.actorKind && MACHINE_ICONS[event.actorKind]
  if (machineIcon) {
    return machineIcon
  }
  if (event.automated && !event.milestone) {
    return IconFlame
  }
  return eventIcons[event.eventType]
}

function EventDot({ event }: { event: TimelineEvent }) {
  const Icon = eventIcon(event)
  const accent = dotAccent(event)

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

// The note's statement already names the person, so the chip would say it
// twice. The avatar alone attributes it and keeps the sentence readable.
function NoteStatement({ event }: { event: TimelineEvent }) {
  const person = event.person
  const milestone = event.milestone

  if (!milestone) {
    return null
  }

  // flex-1 with a zero basis keeps the statement on the same line as the stem
  // and lets a long one wrap inside itself, rather than the whole avatar and
  // sentence dropping to a line of their own.
  return (
    <span className="flex min-w-0 flex-1 items-center gap-2">
      {person && (
        <Avatar className="size-5 shrink-0">
          {person.avatarUrl ? <AvatarImage src={person.avatarUrl} alt={person.name} /> : null}
          <AvatarFallback className="bg-primary/20 text-[10px] font-semibold text-primary">
            {person.initials}
          </AvatarFallback>
        </Avatar>
      )}
      <span className="font-medium text-foreground">{milestone.statement}</span>
    </span>
  )
}

function EventSubject({ event }: { event: TimelineEvent }) {
  if (event.milestone) {
    return <NoteStatement event={event} />
  }
  if (event.person) {
    return <ActorChip actor={event.person} fallback="" />
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
        <ActorChip actor={action.assignee ?? undefined} fallback="Unassigned" />
      </span>
    </button>
  )
}

function PinCard({ pin, withDivider }: { pin: NonNullable<TimelineEvent["pin"]>; withDivider: boolean }) {
  return (
    <div className={withDivider ? "mt-2 border-t border-border pt-2" : ""}>
      {pin.text && (
        <blockquote className="text-sm leading-relaxed text-muted-foreground whitespace-pre-line">
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
  const hasNote = Boolean(event.milestone)
  const hasDetails = Boolean(event.details)
  const hasFile = Boolean(event.file)

  if (!hasChanges && !hasAction && !hasPin && !hasNote && !hasDetails && !hasFile) {
    return null
  }

  return (
    <div className="ml-[44px] mt-2.5 rounded-lg border border-border bg-card px-3.5 py-2.5">
      {event.changes && hasChanges && <ChangeList changes={event.changes} />}
      {event.action && <ActionCard action={event.action} />}
      {event.pin && hasPin && <PinCard pin={event.pin} withDivider={hasChanges || hasAction} />}
      {event.milestone && (
        <NoteQuote milestone={event.milestone} withDivider={hasChanges || hasAction || hasPin} />
      )}
      {event.details && (
        <p className={`text-sm leading-relaxed text-muted-foreground ${hasChanges || hasAction || hasPin || hasNote ? "mt-2 border-t border-border pt-2" : ""}`}>
          {event.details}
        </p>
      )}
      {event.file && (
        <TimelineFileAttachment file={event.file} withDivider={hasChanges || hasAction || hasPin || hasNote || hasDetails} />
      )}
    </div>
  )
}

function EventRow({
  event,
  incidentId,
  canDismiss,
  connected,
}: {
  event: TimelineEvent
  incidentId: string
  canDismiss: boolean
  connected: boolean
}) {
  const highlight = highlightEvents.includes(event.eventType)
  const dismissable = Boolean(event.milestone) && !event.milestone?.dismissedAt && canDismiss

  return (
    <div className="relative pb-5">
      {connected && <div aria-hidden className="absolute left-[14px] top-7 bottom-0 w-px bg-border" />}

      <div className="group flex items-center gap-4">
        <div className="relative z-10 shrink-0">
          <EventDot event={event} />
        </div>

        {/* The sentence wraps on its own. Time and actions sit outside it so a
            long note never pushes them onto a second line. */}
        <div className="flex flex-1 min-w-0 items-center gap-2 flex-wrap text-sm">
          <span className={`font-medium ${highlight ? "text-foreground" : "text-foreground/95"}`}>
            {event.actor}
          </span>
          <span className="text-muted-foreground">{event.description}</span>
          <EventSubject event={event} />
        </div>

        <span className="flex shrink-0 items-center gap-1">
          <span className="text-xs tabular-nums text-muted-foreground/80">
            {formatTime(event.createdAt)}
          </span>
          {dismissable && (
            <span className="opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
              <DismissNoteAction event={event} incidentId={incidentId} />
            </span>
          )}
        </span>
      </div>

      <EventCard event={event} />
    </div>
  )
}

function DismissedNotes({ notes, connected }: { notes: TimelineEvent[]; connected: boolean }) {
  const [expanded, setExpanded] = useState(false)

  function toggle() {
    setExpanded(!expanded)
  }

  const Chevron = expanded ? IconChevronDown : IconChevronRight

  return (
    <div className="relative pb-5">
      {connected && <div aria-hidden className="absolute left-[14px] top-0 bottom-0 w-px bg-border" />}
      <button
        type="button"
        onClick={toggle}
        className="ml-[44px] inline-flex items-center gap-1.5 text-xs text-muted-foreground/80 transition-colors hover:text-foreground"
      >
        <Chevron className="size-3.5" />
        {notes.length === 1 ? "1 dismissed note" : `${notes.length} dismissed notes`}
      </button>

      {expanded && (
        <ul className="ml-[44px] mt-2 flex flex-col gap-2">
          {notes.map((note) => (
            <li
              key={note.id}
              className="rounded-lg border border-dashed border-border px-3.5 py-2.5 text-sm text-muted-foreground/80"
            >
              <p className="line-through decoration-muted-foreground/40">{note.milestone?.statement}</p>
              <p className="mt-1 text-xs text-muted-foreground/70">
                {note.milestone?.dismissedBy
                  ? `Dismissed by ${note.milestone.dismissedBy}`
                  : "Dismissed"}
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

type DayGroup = { key: string; date: string; kept: TimelineEvent[]; dismissed: TimelineEvent[] }

// Dismissed notes leave the run of the day and collect at its end, so a
// correction stays visible without interrupting the story.
function groupByDay(events: TimelineEvent[]): DayGroup[] {
  const groups: DayGroup[] = []

  events.forEach((event) => {
    const date = formatDate(event.createdAt)
    let group = groups[groups.length - 1]
    if (!group || group.date !== date) {
      group = { key: event.id, date, kept: [], dismissed: [] }
      groups.push(group)
    }
    if (event.milestone?.dismissedAt) {
      group.dismissed.push(event)
    } else {
      group.kept.push(event)
    }
  })

  return groups
}

export function IncidentTimeline({
  events,
  incidentId,
  canDismiss,
}: {
  events: TimelineEvent[]
  incidentId: string
  canDismiss: boolean
}) {
  const groups = groupByDay(events)

  return (
    <ol className="relative">
      {groups.map((group, groupIndex) => {
        const isLastGroup = groupIndex === groups.length - 1

        return (
          <li key={group.key} className="relative">
            <div className="relative flex items-center py-6">
              <div aria-hidden className="absolute left-[14px] top-0 bottom-0 w-px bg-border" />
              <div aria-hidden className="relative z-10 ml-[7.5px] size-3.5 rounded-full border border-border bg-muted-foreground" />
              <span className="ml-3 text-xs font-semibold uppercase tracking-[0.15em] text-muted-foreground">
                {group.date}
              </span>
            </div>

            <ol className="relative">
              {group.kept.map((event, index) => (
                <li key={event.id} className="relative">
                  <EventRow
                    event={event}
                    incidentId={incidentId}
                    canDismiss={canDismiss}
                    connected={
                      !isLastGroup ||
                      index < group.kept.length - 1 ||
                      group.dismissed.length > 0
                    }
                  />
                </li>
              ))}
            </ol>

            {group.dismissed.length > 0 && (
              <DismissedNotes notes={group.dismissed} connected={!isLastGroup} />
            )}
          </li>
        )
      })}
    </ol>
  )
}
