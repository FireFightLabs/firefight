import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_TEMPLATE_PARAMS } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { halonWorkflowsPath } from "@/lib/routes"
import { TimeZoneSelect, browserTimeZone } from "@/pages/halon/components/workflows/time-zone-select"
import type { WorkflowTemplateChoice } from "@/pages/halon/components/workflows/types"
import { WeekdayPicker } from "@/pages/halon/components/workflows/weekday-picker"

const WEEKDAYS = [ 1, 2, 3, 4, 5 ]
const DEFAULT_TIME = "09:00"

// The look for probing from the library: which days, at what time, in which time zone.
export function ProbingScanDialog({
  template,
  open,
  onClose,
  timeZones,
}: {
  template: WorkflowTemplateChoice
  open: boolean
  onClose: () => void
  timeZones: string[]
}) {
  const [days, setDays] = useState(WEEKDAYS)
  const [at, setAt] = useState(DEFAULT_TIME)
  const [zone, setZone] = useState(browserTimeZone)
  const [processing, setProcessing] = useState(false)

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    router.post(halonWorkflowsPath(), {
      template: template.key,
      [WORKFLOW_TEMPLATE_PARAMS.DAYS]: days,
      [WORKFLOW_TEMPLATE_PARAMS.AT]: at,
      [WORKFLOW_TEMPLATE_PARAMS.TIME_ZONE]: zone,
    }, { onSuccess: onClose, onFinish: finish })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{template.name}</DialogTitle>
            <DialogDescription>{template.description} It is made as a draft, and runs once it is published.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label>Days</Label>
              <WeekdayPicker days={days} onChange={setDays} />
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="flex flex-col gap-2">
                <Label htmlFor="probing-at">At</Label>
                <Input id="probing-at" type="time" value={at} onChange={(event) => setAt(event.target.value)} />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="probing-zone">Time zone</Label>
                <TimeZoneSelect id="probing-zone" value={zone} onChange={setZone} timeZones={timeZones} />
              </div>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing || days.length === 0}>Make draft</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
