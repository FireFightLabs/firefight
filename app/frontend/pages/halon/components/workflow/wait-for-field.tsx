import { type ChangeEvent, useState } from "react"

import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { WORKFLOW_WAIT } from "@/lib/generated/constants"
import type { JsonObject } from "@/lib/tool-fields"

const UNITS = { MINUTES: "minutes", HOURS: "hours", DAYS: "days" } as const
type Unit = (typeof UNITS)[keyof typeof UNITS]
const MINUTES_IN: Record<Unit, number> = { minutes: 1, hours: 60, days: 1440 }
const UNIT_LABELS: Record<Unit, string> = { minutes: "Minutes", hours: "Hours", days: "Days" }
const WHOLE = /^\s*\d+\s*$/

// How long a step that waits on a person waits, as kept in its settings, a day when it says nothing.
export function savedWait(config: JsonObject): number {
  const saved = config[WORKFLOW_WAIT.KEY]
  return typeof saved === "number" ? saved : WORKFLOW_WAIT.DEFAULT_MINUTES
}

// What is wrong with a wait, or null.
export function waitError(minutes: number | null): string | null {
  if (minutes === null || minutes < WORKFLOW_WAIT.FEWEST_MINUTES || minutes > WORKFLOW_WAIT.MOST_MINUTES) {
    return `Wait from ${WORKFLOW_WAIT.FEWEST_MINUTES} minutes to ${WORKFLOW_WAIT.MOST_MINUTES / MINUTES_IN.days} days, in whole minutes, hours or days.`
  }
  return null
}

function largestUnit(minutes: number): Unit {
  if (minutes % MINUTES_IN.days === 0) {
    return UNITS.DAYS
  }
  return minutes % MINUTES_IN.hours === 0 ? UNITS.HOURS : UNITS.MINUTES
}

interface WaitForFieldProps {
  idPrefix: string
  minutes: number
  // What happens once the wait is over, such as the route the step takes.
  hint: string
  disabled: boolean
  onChange: (minutes: number | null) => void
}

// How long a step that waits on a person waits, as a number and a unit. The step takes its route for nobody answering
// once it is over.
export function WaitForField({ idPrefix, minutes, hint, disabled, onChange }: WaitForFieldProps) {
  const [ unit, setUnit ] = useState<Unit>(() => largestUnit(minutes))
  const [ amount, setAmount ] = useState(() => String(minutes / MINUTES_IN[largestUnit(minutes)]))
  const shown = WHOLE.test(amount) ? Number(amount) * MINUTES_IN[unit] : null
  const error = waitError(shown)

  function typed(event: ChangeEvent<HTMLInputElement>) {
    setAmount(event.target.value)
    onChange(WHOLE.test(event.target.value) ? Number(event.target.value) * MINUTES_IN[unit] : null)
  }

  function chooseUnit(value: string) {
    const chosen = Object.values(UNITS).find((each) => each === value) ?? unit
    setUnit(chosen)
    onChange(WHOLE.test(amount) ? Number(amount) * MINUTES_IN[chosen] : null)
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={`${idPrefix}-wait`} className="text-xs">Wait for</Label>
      <div className="flex gap-1.5">
        <Input id={`${idPrefix}-wait`} value={amount} onChange={typed} inputMode="numeric" disabled={disabled} className="w-24" aria-invalid={error !== null} />
        <Select value={unit} onValueChange={chooseUnit} disabled={disabled}>
          <SelectTrigger className="flex-1" aria-label="Wait unit"><SelectValue /></SelectTrigger>
          <SelectContent>
            {Object.values(UNITS).map((each) => <SelectItem key={each} value={each}>{UNIT_LABELS[each]}</SelectItem>)}
          </SelectContent>
        </Select>
      </div>
      {error ? <p className="text-xs text-destructive">{error}</p> : <p className="text-xs text-fg-muted">{hint}</p>}
    </div>
  )
}
