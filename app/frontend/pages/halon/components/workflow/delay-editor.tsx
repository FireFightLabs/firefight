import { type ChangeEvent, useState } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { WORKFLOW_CONFIG_KEYS, WORKFLOW_DELAY_UNITS, type WorkflowDelayUnit } from "@/lib/generated/constants"
import { REFERENCE, type JsonObject } from "@/lib/tool-fields"
import { DELAY_UNIT_LABELS } from "@/pages/halon/lib/workflow/labels"

const WAYS = { FOR: "for", UNTIL: "until", AT: "at" } as const
type Way = (typeof WAYS)[keyof typeof WAYS]
const WAY_LABELS: Record<Way, string> = { for: "For a while", until: "Until a time of day", at: "Until a moment" }
const TIME_OF_DAY = /^([01]?\d|2[0-3]):([0-5]\d)$/
const NUMBER = /^\s*\d+(\.\d+)?\s*$/
const KEYS = WORKFLOW_CONFIG_KEYS

interface DelayEditorProps {
  idPrefix: string
  config: JsonObject
  timeZones: string[]
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

interface DelayDraft {
  way: Way
  amount: string
  unit: WorkflowDelayUnit
  until: string
  timeZone: string
  at: string
}

function text(value: unknown): string {
  return value === undefined || value === null ? "" : String(value)
}

function delayDraft(config: JsonObject): DelayDraft {
  const unit = WORKFLOW_DELAY_UNITS.find((each) => each in config)
  const way: Way = unit ? WAYS.FOR : KEYS.UNTIL in config ? WAYS.UNTIL : KEYS.AT in config ? WAYS.AT : WAYS.FOR
  return {
    way,
    amount: unit ? text(config[unit]) : "",
    unit: unit ?? WORKFLOW_DELAY_UNITS[1],
    until: text(config[KEYS.UNTIL]),
    timeZone: text(config[KEYS.TIME_ZONE]),
    at: text(config[KEYS.AT]),
  }
}

// The config holds exactly one way to wait, as the engine asks, and the other ways' keys go.
function delayConfig(draft: DelayDraft): JsonObject {
  if (draft.way === WAYS.FOR) {
    const amount = draft.amount.trim()
    return { [draft.unit]: NUMBER.test(amount) ? Number(amount) : amount }
  }
  if (draft.way === WAYS.UNTIL) {
    return draft.timeZone ? { [KEYS.UNTIL]: draft.until.trim(), [KEYS.TIME_ZONE]: draft.timeZone } : { [KEYS.UNTIL]: draft.until.trim() }
  }
  return { [KEYS.AT]: draft.at.trim() }
}

function delayError(draft: DelayDraft): string | null {
  if (draft.way === WAYS.FOR && !NUMBER.test(draft.amount) && !REFERENCE.test(draft.amount)) {
    return "How long, as a number, or a value from an earlier step."
  }
  if (draft.way === WAYS.UNTIL && !TIME_OF_DAY.test(draft.until.trim()) && !REFERENCE.test(draft.until)) {
    return "A time of day written as 09:00."
  }
  if (draft.way === WAYS.AT && draft.at.trim().length === 0) {
    return "The moment to wait until, such as 2026-11-02T07:00:00+01:00, or a value from an earlier step."
  }
  return null
}

// A delay waits a while, until a time of day in a time zone, or until a moment, and the step's time limit has no say.
export function DelayEditor({ idPrefix, config, timeZones, references, disabled, onChange }: DelayEditorProps) {
  const [ draft, setDraft ] = useState<DelayDraft>(() => delayDraft(config))
  const zones = timeZones.map((zone) => ({ value: zone, label: zone }))

  function changed(next: DelayDraft) {
    setDraft(next)
    onChange(delayConfig(next), delayError(next))
  }

  function chooseWay(value: string) {
    const way = Object.values(WAYS).find((each) => each === value)
    if (way) {
      changed({ ...draft, way })
    }
  }

  function typed(field: "amount" | "until" | "at") {
    return (event: ChangeEvent<HTMLInputElement>) => changed({ ...draft, [field]: event.target.value })
  }

  function insert(field: "amount" | "until" | "at") {
    return (reference: string) => changed({ ...draft, [field]: reference })
  }

  function chooseUnit(value: string) {
    changed({ ...draft, unit: WORKFLOW_DELAY_UNITS.find((each) => each === value) ?? draft.unit })
  }

  function chooseZone(value: string | null) {
    changed({ ...draft, timeZone: value ?? "" })
  }

  const error = delayError(draft)

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-way`} className="text-xs">How long it waits</Label>
        <Select value={draft.way} onValueChange={chooseWay} disabled={disabled}>
          <SelectTrigger id={`${idPrefix}-way`} className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            {Object.values(WAYS).map((way) => <SelectItem key={way} value={way}>{WAY_LABELS[way]}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {draft.way === WAYS.FOR && (
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-amount`} className="text-xs">How long</Label>
          <div className="flex gap-1.5">
            <Input id={`${idPrefix}-amount`} value={draft.amount} onChange={typed("amount")} inputMode="numeric" disabled={disabled} className="w-24" />
            <Select value={draft.unit} onValueChange={chooseUnit} disabled={disabled}>
              <SelectTrigger className="flex-1" aria-label="Unit"><SelectValue /></SelectTrigger>
              <SelectContent>
                {WORKFLOW_DELAY_UNITS.map((unit: WorkflowDelayUnit) => <SelectItem key={unit} value={unit}>{DELAY_UNIT_LABELS[unit]}</SelectItem>)}
              </SelectContent>
            </Select>
            {!disabled && <ReferencePicker references={references} label="Wait as long as an earlier value says" onPick={insert("amount")} />}
          </div>
        </div>
      )}
      {draft.way === WAYS.UNTIL && (
        <div className="space-y-2">
          <div className="space-y-1">
            <Label htmlFor={`${idPrefix}-until`} className="text-xs">Time of day</Label>
            <Input id={`${idPrefix}-until`} value={draft.until} onChange={typed("until")} placeholder="09:00" disabled={disabled} className="font-mono" />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`${idPrefix}-zone`} className="text-xs">Time zone</Label>
            <SearchableSelect id={`${idPrefix}-zone`} value={draft.timeZone || null} onValueChange={chooseZone} options={zones} placeholder="UTC unless one is chosen"
                              searchPlaceholder="Search time zones" emptyText="No time zone by that name" disabled={disabled} />
          </div>
        </div>
      )}
      {draft.way === WAYS.AT && (
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-at`} className="text-xs">Moment</Label>
          <div className="flex gap-1.5">
            <Input id={`${idPrefix}-at`} value={draft.at} onChange={typed("at")} placeholder="2026-11-02T07:00:00+01:00" disabled={disabled} className="font-mono text-xs" />
            {!disabled && <ReferencePicker references={references} label="Wait until a moment an earlier step gave" onPick={insert("at")} />}
          </div>
        </div>
      )}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
