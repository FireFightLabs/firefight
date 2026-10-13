import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  WORKFLOW_SCHEDULE_KEYS,
  WORKFLOW_SCHEDULE_LIMITS,
  WORKFLOW_SCHEDULE_REPEATS,
  type WorkflowScheduleRepeat,
} from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { repeatWorkflowPath } from "@/lib/routes"
import { REPEAT_LABELS } from "@/pages/halon/components/workflows/labels"
import { TimeZoneSelect, browserTimeZone } from "@/pages/halon/components/workflows/time-zone-select"
import { WeekdayPicker } from "@/pages/halon/components/workflows/weekday-picker"

const WEEKS = [ "1", "2", "3", "4", "last" ]
const WEEK_LABELS: Record<string, string> = { "1": "First", "2": "Second", "3": "Third", "4": "Fourth", last: "Last" }
const DAY_NAMES = [ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" ]

interface Schedule {
  repeat: WorkflowScheduleRepeat
  every: number
  at: string
  days: number[]
  week: string
  weekday: number
  zone: string
}

const STARTING: Schedule = { repeat: "days", every: 15, at: "09:00", days: [ 1, 2, 3, 4, 5 ], week: "1", weekday: 1, zone: browserTimeZone() }

function chosenRepeat(value: string): WorkflowScheduleRepeat {
  return WORKFLOW_SCHEDULE_REPEATS.find((repeat) => repeat === value) ?? "days"
}

function paramsFor(schedule: Schedule): Record<string, string | number | number[]> {
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

// Makes a one off that ran repeat: a draft with this schedule, published like any change.
export function RepeatDialog({ workflowId, workflowName, onClose, timeZones }: { workflowId: string | null; workflowName: string; onClose: () => void; timeZones: string[] }) {
  const [schedule, setSchedule] = useState<Schedule>(STARTING)
  const [processing, setProcessing] = useState(false)

  function change<Key extends keyof Schedule>(key: Key, value: Schedule[Key]) {
    setSchedule((current) => ({ ...current, [key]: value }))
  }

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!workflowId) {
      return
    }
    setProcessing(true)
    router.post(repeatWorkflowPath(workflowId), paramsFor(schedule), { onSuccess: onClose, onFinish: finish })
  }

  const everyLimits = schedule.repeat === "minutes"
    ? { min: WORKFLOW_SCHEDULE_LIMITS.MINUTES_MIN, max: WORKFLOW_SCHEDULE_LIMITS.MINUTES_MAX, unit: "minutes" }
    : { min: WORKFLOW_SCHEDULE_LIMITS.HOURS_MIN, max: WORKFLOW_SCHEDULE_LIMITS.HOURS_MAX, unit: "hours" }
  const asksEvery = schedule.repeat === "minutes" || schedule.repeat === "hours"
  const asksTime = schedule.repeat !== "minutes"

  return (
    <Dialog open={Boolean(workflowId)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Make {workflowName} repeat</DialogTitle>
            <DialogDescription>It gets a draft that runs on this schedule. Publishing the draft starts it.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="repeat-kind">Repeats</Label>
              <Select value={schedule.repeat} onValueChange={(value) => change("repeat", chosenRepeat(value))}>
                <SelectTrigger id="repeat-kind" className="w-full"><SelectValue /></SelectTrigger>
                <SelectContent>
                  {WORKFLOW_SCHEDULE_REPEATS.map((repeat) => (
                    <SelectItem key={repeat} value={repeat}>{REPEAT_LABELS[repeat]}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            {asksEvery && (
              <div className="flex flex-col gap-2">
                <Label htmlFor="repeat-every">Every how many {everyLimits.unit}</Label>
                <Input id="repeat-every" type="number" min={everyLimits.min} max={everyLimits.max} value={schedule.every}
                  onChange={(event) => change("every", Number(event.target.value))} />
              </div>
            )}
            {schedule.repeat === "days" && (
              <div className="flex flex-col gap-2">
                <Label>Days</Label>
                <WeekdayPicker days={schedule.days} onChange={(days) => change("days", days)} />
              </div>
            )}
            {schedule.repeat === "monthly" && (
              <div className="grid grid-cols-2 gap-4">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="repeat-week">Week</Label>
                  <Select value={schedule.week} onValueChange={(value) => change("week", value)}>
                    <SelectTrigger id="repeat-week" className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {WEEKS.map((week) => <SelectItem key={week} value={week}>{WEEK_LABELS[week]}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="repeat-weekday">Day</Label>
                  <Select value={String(schedule.weekday)} onValueChange={(value) => change("weekday", Number(value))}>
                    <SelectTrigger id="repeat-weekday" className="w-full"><SelectValue /></SelectTrigger>
                    <SelectContent>
                      {DAY_NAMES.map((day, index) => <SelectItem key={day} value={String(index)}>{day}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>
            )}
            {asksTime && (
              <div className="flex flex-col gap-2">
                <Label htmlFor="repeat-at">{schedule.repeat === "hours" ? "At minute, written as a time such as 00:15" : "At"}</Label>
                <Input id="repeat-at" type="time" value={schedule.at} onChange={(event) => change("at", event.target.value)} />
              </div>
            )}
            <div className="flex flex-col gap-2">
              <Label htmlFor="repeat-zone">Time zone</Label>
              <TimeZoneSelect id="repeat-zone" value={schedule.zone} onChange={(zone) => change("zone", zone)} timeZones={timeZones} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>Make the draft</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
