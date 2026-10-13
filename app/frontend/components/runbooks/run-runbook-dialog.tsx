import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { VisitOptions } from "@inertiajs/core"

import { Button } from "@/components/ui/button"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { runbookRunsPath } from "@/lib/routes"
import { InputsFields, defaultValues } from "@/pages/halon/components/workflows/inputs-fields"
import type { RunbookWorkflow } from "@/types/serializers"

export interface RunbookRunTarget {
  runbookId: string
  runbookName: string
  workflow: RunbookWorkflow
  incidentId?: string
}

export function RunRunbookDialog({ target, onClose, visitOptions }: { target: RunbookRunTarget | null; onClose: () => void; visitOptions?: VisitOptions }) {
  const [values, setValues] = useState<Record<string, string>>({})
  const [processing, setProcessing] = useState(false)
  const [seededFor, setSeededFor] = useState<string | null>(null)
  if (target && seededFor !== target.runbookId) {
    setSeededFor(target.runbookId)
    setValues(defaultValues(target.workflow.inputs))
  }

  function change(key: string, value: string) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  function finish() {
    setProcessing(false)
    setSeededFor(null)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!target) {
      return
    }
    setProcessing(true)
    router.post(
      runbookRunsPath(target.runbookId),
      { inputs: values, incident_id: target.incidentId ?? null },
      { preserveScroll: true, ...visitOptions, onSuccess: onClose, onFinish: finish },
    )
  }

  return (
    <Dialog open={Boolean(target)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Run {target?.runbookName}</DialogTitle>
            <DialogDescription>
              It runs the {target?.workflow.name} workflow now, as the workflow itself with only what an admin granted it.
            </DialogDescription>
          </DialogHeader>
          <div className="py-4">
            <InputsFields idPrefix="runbook-run-input" inputs={target?.workflow.inputs ?? []} values={values} onChange={change} />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>Run</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
