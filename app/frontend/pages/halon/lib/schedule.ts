import { WORKFLOW_SCHEDULE_KEYS, WORKFLOW_SCHEDULE_REPEATS, WORKFLOW_TRIGGER_EDITOR, type WorkflowScheduleRepeat, type WorkflowScheduleWeek } from "@/lib/generated/constants"
import { jsonObject, type JsonObject } from "@/lib/tool-fields"
import { browserTimeZone } from "@/pages/halon/components/workflows/time-zone-select"
import type { WorkflowTriggerKind } from "@/types/serializers"

// A repeating schedule as its form holds it. Only the keys its repeat reads are written back (scheduleParams).
export interface Schedule {
  repeat: WorkflowScheduleRepeat
  every: number
  at: string
  days: number[]
  week: string
  weekday: number
  zone: string
}

export const WEEK_LABELS: Record<WorkflowScheduleWeek, string> = { "1": "First", "2": "Second", "3": "Third", "4": "Fourth", last: "Last" }
export const DAY_NAMES = [ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]

export function startingSchedule(): Schedule {
  return { repeat: "days", every: 15, at: "09:00", days: [ 1, 2, 3, 4, 5 ], week: "1", weekday: 1, zone: browserTimeZone() }
}

export function chosenRepeat(value: string): WorkflowScheduleRepeat {
  return WORKFLOW_SCHEDULE_REPEATS.find((repeat) => repeat === value) ?? "days"
}

function numberOf(value: unknown, fallback: number): number {
  const parsed = typeof value === "number" ? value : Number(value)
  return Number.isFinite(parsed) ? parsed : fallback
}

// A stored trigger read back into the form, each missing key from where a new schedule starts.
export function scheduleFrom(config: Record<string, unknown>): Schedule {
  const starting = startingSchedule()
  const days = config[WORKFLOW_SCHEDULE_KEYS.DAYS]
  return {
    repeat: chosenRepeat(String(config[WORKFLOW_SCHEDULE_KEYS.REPEAT] ?? starting.repeat)),
    every: numberOf(config[WORKFLOW_SCHEDULE_KEYS.EVERY], starting.every),
    at: typeof config[WORKFLOW_SCHEDULE_KEYS.AT] === "string" ? String(config[WORKFLOW_SCHEDULE_KEYS.AT]) : starting.at,
    days: Array.isArray(days) ? days.map((day) => numberOf(day, 0)) : starting.days,
    week: config[WORKFLOW_SCHEDULE_KEYS.WEEK_OF_MONTH] == null ? starting.week : String(config[WORKFLOW_SCHEDULE_KEYS.WEEK_OF_MONTH]),
    weekday: numberOf(config[WORKFLOW_SCHEDULE_KEYS.WEEKDAY], starting.weekday),
    zone: typeof config[WORKFLOW_SCHEDULE_KEYS.TIME_ZONE] === "string" ? String(config[WORKFLOW_SCHEDULE_KEYS.TIME_ZONE]) : starting.zone,
  }
}

// What a schedule stores, only the keys its repeat reads.
export function scheduleParams(schedule: Schedule): JsonObject {
  const base = { [WORKFLOW_SCHEDULE_KEYS.REPEAT]: schedule.repeat, [WORKFLOW_SCHEDULE_KEYS.TIME_ZONE]: schedule.zone }
  switch (schedule.repeat) {
    case "minutes":
      return { ...base, [WORKFLOW_SCHEDULE_KEYS.EVERY]: schedule.every }
    case "hours":
      return { ...base, [WORKFLOW_SCHEDULE_KEYS.EVERY]: schedule.every, [WORKFLOW_SCHEDULE_KEYS.AT]: schedule.at }
    case "days":
      return { ...base, [WORKFLOW_SCHEDULE_KEYS.AT]: schedule.at, [WORKFLOW_SCHEDULE_KEYS.DAYS]: schedule.days }
    case "monthly":
      return {
        ...base, [WORKFLOW_SCHEDULE_KEYS.AT]: schedule.at, [WORKFLOW_SCHEDULE_KEYS.WEEK_OF_MONTH]: schedule.week,
        [WORKFLOW_SCHEDULE_KEYS.WEEKDAY]: schedule.weekday,
      }
  }
}

// When a one off runs, as its form holds it: a local date and time and the zone it is on.
export interface OnceAt {
  at: string
  zone: string
}

// Tomorrow at 09:00, which a new one starts at.
function tomorrowMorning(): string {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000)
  const month = String(tomorrow.getMonth() + 1).padStart(2, "0")
  const day = String(tomorrow.getDate()).padStart(2, "0")
  return `${tomorrow.getFullYear()}-${month}-${day}T09:00`
}

export function onceAtFrom(config: Record<string, unknown>): OnceAt {
  const at = config[WORKFLOW_SCHEDULE_KEYS.AT]
  const zone = config[WORKFLOW_SCHEDULE_KEYS.TIME_ZONE]
  return { at: typeof at === "string" && at.includes("T") ? at : tomorrowMorning(), zone: typeof zone === "string" ? zone : browserTimeZone() }
}

export function onceAtParams(onceAt: OnceAt): JsonObject {
  return { [WORKFLOW_SCHEDULE_KEYS.AT]: onceAt.at, [WORKFLOW_SCHEDULE_KEYS.TIME_ZONE]: onceAt.zone }
}

// What a trigger chosen from the palette starts with: its kind's defaults, and for a timed kind the person's own time
// zone and, for a one off, tomorrow morning.
export function startingTrigger(kind: WorkflowTriggerKind): JsonObject {
  const defaults = jsonObject(kind.defaults)
  if (kind.editor === WORKFLOW_TRIGGER_EDITOR.SCHEDULE) {
    return { ...defaults, ...scheduleParams(scheduleFrom(defaults)) }
  }
  if (kind.editor === WORKFLOW_TRIGGER_EDITOR.ONCE_AT) {
    return { ...defaults, ...onceAtParams(onceAtFrom(defaults)) }
  }
  return defaults
}
