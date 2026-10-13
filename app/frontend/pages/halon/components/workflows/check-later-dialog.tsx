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

const HALF_AN_HOUR_MS = 30 * 60 * 1000

// Half an hour from now on the browser's clock, as a date and time field writes it.
function inHalfAnHour(): string {
  const later = new Date(Date.now() + HALF_AN_HOUR_MS)
  const pad = (value: number) => String(value).padStart(2, "0")
  return `${later.getFullYear()}-${pad(later.getMonth() + 1)}-${pad(later.getDate())}T${pad(later.getHours())}:${pad(later.getMinutes())}`
}

// A one off from the library: what to check, when, and where the verdict is posted.
export function CheckLaterDialog({
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
  const [resource, setResource] = useState("")
  const [at, setAt] = useState(inHalfAnHour)
  const [zone, setZone] = useState(browserTimeZone)
  const [channel, setChannel] = useState("")
  const [processing, setProcessing] = useState(false)

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    setProcessing(true)
    router.post(halonWorkflowsPath(), {
      template: template.key,
      [WORKFLOW_TEMPLATE_PARAMS.RESOURCE]: resource,
      [WORKFLOW_TEMPLATE_PARAMS.AT]: at,
      [WORKFLOW_TEMPLATE_PARAMS.TIME_ZONE]: zone,
      [WORKFLOW_TEMPLATE_PARAMS.CHANNEL]: channel,
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
              <Label htmlFor="check-later-resource">What to check</Label>
              <Input id="check-later-resource" placeholder="web" value={resource} onChange={(event) => setResource(event.target.value)} />
              <p className="text-xs text-muted-foreground">A resource on the map, by its name.</p>
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="flex flex-col gap-2">
                <Label htmlFor="check-later-at">When</Label>
                <Input id="check-later-at" type="datetime-local" value={at} onChange={(event) => setAt(event.target.value)} />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="check-later-zone">Time zone</Label>
                <TimeZoneSelect id="check-later-zone" value={zone} onChange={setZone} timeZones={timeZones} />
              </div>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="check-later-channel">Post the verdict in</Label>
              <Input id="check-later-channel" placeholder="#ops" value={channel} onChange={(event) => setChannel(event.target.value)} />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>Make draft</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
