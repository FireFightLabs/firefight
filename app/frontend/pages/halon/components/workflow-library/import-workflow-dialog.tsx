import { useState, type ChangeEvent, type FormEvent } from "react"
import type { Errors } from "@inertiajs/core"
import { router } from "@inertiajs/react"

import { FormErrors } from "@/components/form-errors"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { WORKFLOW_FILE_EXTENSION } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { importHalonWorkflowPath } from "@/lib/routes"

interface ImportWorkflowDialogProps {
  open: boolean
  onClose: () => void
}

// Brings in a workflow exported from Firefight, here or in another workspace, as a new draft. Nothing runs until someone
// publishes it, and a file holding anything shaped like a credential is refused.
export function ImportWorkflowDialog({ open, onClose }: ImportWorkflowDialogProps) {
  const [ file, setFile ] = useState<File | null>(null)
  const [ name, setName ] = useState("")
  const [ errors, setErrors ] = useState<Errors>({})
  const [ processing, setProcessing ] = useState(false)

  function choose(event: ChangeEvent<HTMLInputElement>) {
    setFile(event.target.files?.[0] ?? null)
    setErrors({})
  }

  function writeName(event: ChangeEvent<HTMLInputElement>) {
    setName(event.target.value)
  }

  function close() {
    setFile(null)
    setName("")
    setErrors({})
    onClose()
  }

  function showErrors(received: Errors) {
    setErrors(received)
  }

  function doneSending() {
    setProcessing(false)
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (!file) {
      return
    }
    setProcessing(true)
    router.post(importHalonWorkflowPath(), { file, name }, { forceFormData: true, preserveScroll: true, onSuccess: close, onError: showErrors, onFinish: doneSending })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Import a workflow</DialogTitle>
            <DialogDescription>
              Choose a {WORKFLOW_FILE_EXTENSION} file exported from Firefight. It arrives as a draft, and runs once someone publishes it.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="workflow-import-file">File</Label>
              <Input id="workflow-import-file" type="file" accept=".json,application/json" onChange={choose} aria-invalid={Boolean(errors.file)} />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="workflow-import-name">Name (optional)</Label>
              <Input id="workflow-import-name" value={name} onChange={writeName} placeholder="The name the file gives it" />
            </div>
            <FormErrors errors={errors} />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={!file || processing}>Import</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
