import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { TimeZoneSelect } from "@/pages/halon/components/workflows/time-zone-select"
import type { OnceAt } from "@/pages/halon/lib/schedule"

interface OnceAtFieldsProps {
  idPrefix: string
  onceAt: OnceAt
  timeZones: string[]
  disabled?: boolean
  onChange: (onceAt: OnceAt) => void
}

// When a one off runs: a date and time on its own time zone's clock.
export function OnceAtFields({ idPrefix, onceAt, timeZones, disabled = false, onChange }: OnceAtFieldsProps) {
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor={`${idPrefix}-at`}>Runs at</Label>
        <Input id={`${idPrefix}-at`} type="datetime-local" value={onceAt.at} disabled={disabled} onChange={(event) => onChange({ ...onceAt, at: event.target.value })} />
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor={`${idPrefix}-zone`}>Time zone</Label>
        <TimeZoneSelect id={`${idPrefix}-zone`} value={onceAt.zone} onChange={(zone) => onChange({ ...onceAt, zone })} timeZones={timeZones} disabled={disabled} />
      </div>
    </div>
  )
}
