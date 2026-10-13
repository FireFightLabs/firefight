import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Dialog, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { whenClosed } from "@/lib/handlers"
import { runWorkflowPath } from "@/lib/routes"
import { InputsFields, defaultValues } from "@/pages/halon/components/workflows/inputs-fields"
import type { WorkflowInput } from "@/pages/halon/components/workflows/types"

export interface RunTarget {
  id: string
  name: string
  inputs: WorkflowInput[]
}

// Runs a published workflow by hand, asking its trigger's questions first.
export function RunDialog({ target, onClose }: { target: RunTarget | null; onClose: () => void }) {
  const [values, setValues] = useState<Record<string, string>>({})
  const [processing, setProcessing] = useState(false)
  const [seededFor, setSeededFor] = useState<string | null>(null)
  if (target && seededFor !== target.id) {
    setSeededFor(target.id)
    setValues(defaultValues(target.inputs))
  }

  function change(key: string, value: string) {
    setValues((current) => ({ ...current, [key]: value }))
  }

  function finish() {
    setProcessing(false)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!target) {
      return
    }
    setProcessing(true)
    router.post(runWorkflowPath(target.id), { inputs: values }, { onSuccess: onClose, onFinish: finish })
  }

  return (
    <Dialog open={Boolean(target)} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Run {target?.name}</DialogTitle>
            <DialogDescription>It runs now as the workflow, with only what it was granted, and its run opens.</DialogDescription>
          </DialogHeader>
          <div className="py-4">
            <InputsFields idPrefix="run-input" inputs={target?.inputs ?? []} values={values} onChange={change} />
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
