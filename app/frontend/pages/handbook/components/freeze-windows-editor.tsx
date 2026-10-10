import { IconPlus, IconSnowflake, IconTrash } from "@tabler/icons-react"
import { type ChangeEvent, useMemo } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  HANDBOOK_FREEZE_LIFTED_BY_LIMIT,
  HANDBOOK_FREEZE_NAME_LIMIT,
  HANDBOOK_FREEZE_REPEATS,
  HANDBOOK_FREEZE_WINDOWS_PER_PAGE,
} from "@/lib/generated/constants"
import type { HandbookFreezeWindow } from "@/types/serializers"

export interface FreezeWindowDraft {
  // Only the form's own key for the row, never sent as part of the window.
  key: string
  name: string
  repeat: HandbookFreezeWindow["repeat"]
  time_zone: string
  start_day: number
  start_time: string
  end_day: number
  end_time: string
  starts_on: string
  starts_clock: string
  ends_on: string
  ends_clock: string
  lifted_by: string
}

const WEEKDAYS = [ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]
const FRIDAY = 5
const MONDAY = 1
const REPEAT_LABELS = [
  { value: HANDBOOK_FREEZE_REPEATS.WEEKLY, label: "Every week" },
  { value: HANDBOOK_FREEZE_REPEATS.ONCE, label: "Once" },
]

function browserTimeZone(): string {
  return Intl.DateTimeFormat().resolvedOptions().timeZone
}

function newKey(): string {
  return crypto.randomUUID()
}

// A date and time on the window's own clock, split for its date and time fields.
function splitLocal(value: string | undefined): [ string, string ] {
  const [ date = "", clock = "" ] = (value ?? "").split("T")
  return [ date, clock ]
}

export function draftOf(window: HandbookFreezeWindow): FreezeWindowDraft {
  const [ startsOn, startsClock ] = splitLocal(window.startsAt)
  const [ endsOn, endsClock ] = splitLocal(window.endsAt)
  return {
    key: newKey(),
    name: window.name,
    repeat: window.repeat,
    time_zone: window.timeZone,
    start_day: window.startDay ?? FRIDAY,
    start_time: window.startTime ?? "15:00",
    end_day: window.endDay ?? MONDAY,
    end_time: window.endTime ?? "08:00",
    starts_on: startsOn,
    starts_clock: startsClock || "00:00",
    ends_on: endsOn,
    ends_clock: endsClock || "00:00",
    lifted_by: window.liftedBy ?? "",
  }
}

export function blankDraft(): FreezeWindowDraft {
  return {
    key: newKey(), name: "", repeat: HANDBOOK_FREEZE_REPEATS.WEEKLY, time_zone: browserTimeZone(), start_day: FRIDAY, start_time: "15:00",
    end_day: MONDAY, end_time: "08:00", starts_on: "", starts_clock: "00:00", ends_on: "", ends_clock: "00:00", lifted_by: "",
  }
}

// What the server reads, only the fields the window's repeat uses.
export function windowOf(draft: FreezeWindowDraft) {
  const shared = { name: draft.name, repeat: draft.repeat, time_zone: draft.time_zone, lifted_by: draft.lifted_by }
  if (draft.repeat === HANDBOOK_FREEZE_REPEATS.WEEKLY) {
    return { ...shared, start_day: draft.start_day, start_time: draft.start_time, end_day: draft.end_day, end_time: draft.end_time }
  }
  return { ...shared, starts_at: `${draft.starts_on}T${draft.starts_clock}`, ends_at: `${draft.ends_on}T${draft.ends_clock}` }
}

interface FreezeWindowsEditorProps {
  windows: FreezeWindowDraft[]
  timeZones: string[]
  onChange: (windows: FreezeWindowDraft[]) => void
}

// The freezes a page sets, each a name, when it holds and who may lift it. Halon reads each as a sentence, and Firefight
// holds back every plan that would run inside one.
export function FreezeWindowsEditor({ windows, timeZones, onChange }: FreezeWindowsEditorProps) {
  const zoneOptions = useMemo(() => timeZones.map((zone) => ({ value: zone, label: zone.split("_").join(" ") })), [ timeZones ])

  function add() {
    onChange([ ...windows, blankDraft() ])
  }

  function change(key: string, patch: Partial<FreezeWindowDraft>) {
    onChange(windows.map((window) => (window.key === key ? { ...window, ...patch } : window)))
  }

  function remove(key: string) {
    onChange(windows.filter((window) => window.key !== key))
  }

  return (
    <section className="flex flex-col gap-3" aria-labelledby="handbook-freeze-windows">
      <div className="flex flex-col gap-1">
        <h3 id="handbook-freeze-windows" className="text-sm font-medium text-fg-primary">Freeze windows</h3>
        <p className="text-xs text-muted-foreground">Halon reads each window, and Firefight holds back every plan that would run inside one.</p>
      </div>
      {windows.map((window) => (
        <FreezeWindowRow key={window.key} window={window} zoneOptions={zoneOptions} onChange={change} onRemove={remove} />
      ))}
      {windows.length < HANDBOOK_FREEZE_WINDOWS_PER_PAGE && (
        <Button type="button" variant="outline" size="sm" className="self-start" onClick={add}>
          <IconPlus className="size-4" />
          Add freeze window
        </Button>
      )}
    </section>
  )
}

interface FreezeWindowRowProps {
  window: FreezeWindowDraft
  zoneOptions: SearchableSelectOption[]
  onChange: (key: string, patch: Partial<FreezeWindowDraft>) => void
  onRemove: (key: string) => void
}

function FreezeWindowRow({ window, zoneOptions, onChange, onRemove }: FreezeWindowRowProps) {
  const id = (field: string) => `freeze-${window.key}-${field}`
  const weekly = window.repeat === HANDBOOK_FREEZE_REPEATS.WEEKLY

  function set(patch: Partial<FreezeWindowDraft>) {
    onChange(window.key, patch)
  }

  function fromInput(field: keyof FreezeWindowDraft) {
    return (event: ChangeEvent<HTMLInputElement>) => set({ [field]: event.target.value })
  }

  function chooseRepeat(value: string) {
    set({ repeat: value === HANDBOOK_FREEZE_REPEATS.ONCE ? HANDBOOK_FREEZE_REPEATS.ONCE : HANDBOOK_FREEZE_REPEATS.WEEKLY })
  }

  function chooseTimeZone(value: string | null) {
    if (value) {
      set({ time_zone: value })
    }
  }

  function removeThis() {
    onRemove(window.key)
  }

  return (
    <div className="flex flex-col gap-4 rounded-md border bg-surface-card p-4">
      <div className="flex items-end gap-3">
        <div className="flex min-w-0 flex-1 flex-col gap-2">
          <Label htmlFor={id("name")} className="flex items-center gap-1.5">
            <IconSnowflake className="size-3.5 text-fg-muted" />
            Name
          </Label>
          <Input id={id("name")} value={window.name} onChange={fromInput("name")} maxLength={HANDBOOK_FREEZE_NAME_LIMIT} placeholder="Such as Friday afternoons" />
        </div>
        <Button type="button" variant="ghost" size="icon" onClick={removeThis} aria-label={`Remove ${window.name || "this freeze window"}`}>
          <IconTrash className="size-4" />
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-2">
          <Label htmlFor={id("repeat")}>Repeats</Label>
          <Select value={window.repeat} onValueChange={chooseRepeat}>
            <SelectTrigger id={id("repeat")} className="w-full">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {REPEAT_LABELS.map((repeat) => (
                <SelectItem key={repeat.value} value={repeat.value}>{repeat.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor={id("zone")}>Time zone</Label>
          <SearchableSelect
            id={id("zone")}
            value={window.time_zone}
            onValueChange={chooseTimeZone}
            options={zoneOptions}
            placeholder="Pick a time zone"
            searchPlaceholder="Search time zones"
            emptyText="No time zones match"
          />
        </div>
      </div>

      {weekly ? (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <WeeklyMoment label="From" dayId={id("start-day")} timeId={id("start-time")} day={window.start_day} time={window.start_time}
                        onDay={(day) => set({ start_day: day })} onTime={fromInput("start_time")} />
          <WeeklyMoment label="Until" dayId={id("end-day")} timeId={id("end-time")} day={window.end_day} time={window.end_time}
                        onDay={(day) => set({ end_day: day })} onTime={fromInput("end_time")} />
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <OnceMoment label="From" dateId={id("starts-on")} timeId={id("starts-clock")} date={window.starts_on} time={window.starts_clock}
                      onDate={fromInput("starts_on")} onTime={fromInput("starts_clock")} />
          <OnceMoment label="Until" dateId={id("ends-on")} timeId={id("ends-clock")} date={window.ends_on} time={window.ends_clock}
                      onDate={fromInput("ends_on")} onTime={fromInput("ends_clock")} />
        </div>
      )}

      <div className="flex flex-col gap-2">
        <Label htmlFor={id("lifted-by")}>Who may lift it <span className="font-normal text-muted-foreground">(optional)</span></Label>
        <Input id={id("lifted-by")} value={window.lifted_by} onChange={fromInput("lifted_by")} maxLength={HANDBOOK_FREEZE_LIFTED_BY_LIMIT}
               placeholder="Such as the CTO" />
      </div>
    </div>
  )
}

interface WeeklyMomentProps {
  label: string
  dayId: string
  timeId: string
  day: number
  time: string
  onDay: (day: number) => void
  onTime: (event: ChangeEvent<HTMLInputElement>) => void
}

function WeeklyMoment({ label, dayId, timeId, day, time, onDay, onTime }: WeeklyMomentProps) {
  function chooseDay(value: string) {
    onDay(Number(value))
  }

  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-2 text-sm font-medium">{label}</legend>
      <div className="flex gap-2">
        <Select value={String(day)} onValueChange={chooseDay}>
          <SelectTrigger id={dayId} className="min-w-0 flex-1" aria-label={`${label} day`}>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {WEEKDAYS.map((weekday, index) => (
              <SelectItem key={weekday} value={String(index)}>{weekday}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Input id={timeId} type="time" value={time} onChange={onTime} className="w-36 shrink-0" aria-label={`${label} time`} />
      </div>
    </fieldset>
  )
}

interface OnceMomentProps {
  label: string
  dateId: string
  timeId: string
  date: string
  time: string
  onDate: (event: ChangeEvent<HTMLInputElement>) => void
  onTime: (event: ChangeEvent<HTMLInputElement>) => void
}

function OnceMoment({ label, dateId, timeId, date, time, onDate, onTime }: OnceMomentProps) {
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-2 text-sm font-medium">{label}</legend>
      <div className="flex gap-2">
        <Input id={dateId} type="date" value={date} onChange={onDate} className="min-w-0 flex-1" aria-label={`${label} date`} />
        <Input id={timeId} type="time" value={time} onChange={onTime} className="w-36 shrink-0" aria-label={`${label} time`} />
      </div>
    </fieldset>
  )
}
