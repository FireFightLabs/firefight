import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { repeatWorkflowPath } from "@/lib/routes"
import { ScheduleFields } from "@/pages/halon/components/workflows/schedule-fields"
import { type Schedule, scheduleParams, startingSchedule } from "@/pages/halon/lib/schedule"

// Makes a one off that ran repeat: a draft with this schedule, published like any change.
export function RepeatDialog({ workflowId, workflowName, onClose, timeZones }: { workflowId: string | null; workflowName: string; onClose: () => void; timeZones: string[] }) {
  const [schedule, setSchedule] = useState<Schedule>(startingSchedule)
  const [processing, setProcessing] = useState(false)

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!workflowId) {
      return
    }
    setProcessing(true)
    router.post(repeatWorkflowPath(workflowId), scheduleParams(schedule), { onSuccess: onClose, onFinish: finish })
  }

  return (
    <Dialog open={Boolean(workflowId)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Make {workflowName} repeat</DialogTitle>
            <DialogDescription>It gets a draft that runs on this schedule. Publishing the draft starts it.</DialogDescription>
          </DialogHeader>
          <div className="py-4">
            <ScheduleFields idPrefix="repeat" schedule={schedule} timeZones={timeZones} onChange={setSchedule} />
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
