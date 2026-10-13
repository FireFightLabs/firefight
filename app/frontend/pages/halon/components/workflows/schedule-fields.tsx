import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { WORKFLOW_SCHEDULE_LIMITS, WORKFLOW_SCHEDULE_REPEATS } from "@/lib/generated/constants"
import { REPEAT_LABELS } from "@/pages/halon/components/workflows/labels"
import { TimeZoneSelect } from "@/pages/halon/components/workflows/time-zone-select"
import { WeekdayPicker } from "@/pages/halon/components/workflows/weekday-picker"
import { chosenRepeat, DAY_NAMES, type Schedule, WEEK_LABELS, WEEKS } from "@/pages/halon/lib/schedule"

interface ScheduleFieldsProps {
  idPrefix: string
  schedule: Schedule
  timeZones: string[]
  disabled?: boolean
  onChange: (schedule: Schedule) => void
}

// When a repeating workflow runs: every few minutes or hours, on days of the week at a time, or on one weekday of the
// month, in its own time zone. Making a one off repeat and a schedule trigger on the canvas both ask it this way.
export function ScheduleFields({ idPrefix, schedule, timeZones, disabled = false, onChange }: ScheduleFieldsProps) {
  function change<Key extends keyof Schedule>(key: Key, value: Schedule[Key]) {
    onChange({ ...schedule, [key]: value })
  }

  const everyLimits = schedule.repeat === "minutes"
    ? { min: WORKFLOW_SCHEDULE_LIMITS.MINUTES_MIN, max: WORKFLOW_SCHEDULE_LIMITS.MINUTES_MAX, unit: "minutes" }
    : { min: WORKFLOW_SCHEDULE_LIMITS.HOURS_MIN, max: WORKFLOW_SCHEDULE_LIMITS.HOURS_MAX, unit: "hours" }
  const asksEvery = schedule.repeat === "minutes" || schedule.repeat === "hours"
  const asksTime = schedule.repeat !== "minutes"

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor={`${idPrefix}-kind`}>Repeats</Label>
        <Select value={schedule.repeat} disabled={disabled} onValueChange={(value) => change("repeat", chosenRepeat(value))}>
          <SelectTrigger id={`${idPrefix}-kind`} className="w-full"><SelectValue /></SelectTrigger>
          <SelectContent>
            {WORKFLOW_SCHEDULE_REPEATS.map((repeat) => (
              <SelectItem key={repeat} value={repeat}>{REPEAT_LABELS[repeat]}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {asksEvery && (
        <div className="flex flex-col gap-2">
          <Label htmlFor={`${idPrefix}-every`}>Every how many {everyLimits.unit}</Label>
          <Input id={`${idPrefix}-every`} type="number" min={everyLimits.min} max={everyLimits.max} value={schedule.every} disabled={disabled}
            onChange={(event) => change("every", Number(event.target.value))} />
        </div>
      )}
      {schedule.repeat === "days" && (
        <div className="flex flex-col gap-2">
          <Label>Days</Label>
          <WeekdayPicker days={schedule.days} disabled={disabled} onChange={(days) => change("days", days)} />
        </div>
      )}
      {schedule.repeat === "monthly" && (
        <div className="grid grid-cols-2 gap-4">
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${idPrefix}-week`}>Week</Label>
            <Select value={schedule.week} disabled={disabled} onValueChange={(value) => change("week", value)}>
              <SelectTrigger id={`${idPrefix}-week`} className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {WEEKS.map((week) => <SelectItem key={week} value={week}>{WEEK_LABELS[week]}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor={`${idPrefix}-weekday`}>Day</Label>
            <Select value={String(schedule.weekday)} disabled={disabled} onValueChange={(value) => change("weekday", Number(value))}>
              <SelectTrigger id={`${idPrefix}-weekday`} className="w-full"><SelectValue /></SelectTrigger>
              <SelectContent>
                {DAY_NAMES.map((day, index) => <SelectItem key={day} value={String(index)}>{day}</SelectItem>)}
              </SelectContent>
            </Select>
          </div>
        </div>
      )}
      {asksTime && (
        <div className="flex flex-col gap-2">
          <Label htmlFor={`${idPrefix}-at`}>{schedule.repeat === "hours" ? "At minute, written as a time such as 00:15" : "At"}</Label>
          <Input id={`${idPrefix}-at`} type="time" value={schedule.at} disabled={disabled} onChange={(event) => change("at", event.target.value)} />
        </div>
      )}
      <div className="flex flex-col gap-2">
        <Label htmlFor={`${idPrefix}-zone`}>Time zone</Label>
        <TimeZoneSelect id={`${idPrefix}-zone`} value={schedule.zone} onChange={(zone) => change("zone", zone)} timeZones={timeZones} disabled={disabled} />
      </div>
    </div>
  )
}
