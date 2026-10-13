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
import { SKILL_FILE_NAME } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"
import { importHalonSkillsPath } from "@/lib/routes"

interface ImportSkillDialogProps {
  open: boolean
  onClose: () => void
}

// Brings in a skill written elsewhere as a SKILL.md file. A file naming a skill the workspace has becomes its next
// version, and one naming Firefight's makes the workspace's copy of it.
export function ImportSkillDialog({ open, onClose }: ImportSkillDialogProps) {
  const [ file, setFile ] = useState<File | null>(null)
  const [ errors, setErrors ] = useState<Errors>({})
  const [ processing, setProcessing ] = useState(false)

  function choose(event: ChangeEvent<HTMLInputElement>) {
    setFile(event.target.files?.[0] ?? null)
    setErrors({})
  }

  function close() {
    setFile(null)
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
    router.post(importHalonSkillsPath(), { file }, { forceFormData: true, preserveScroll: true, onSuccess: close, onError: showErrors, onFinish: doneSending })
  }

  return (
    <Dialog open={open} onOpenChange={whenClosed(close)}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Import a skill</DialogTitle>
            <DialogDescription>
              Choose a {SKILL_FILE_NAME} file. If it names one of your skills it becomes that skill&apos;s next version, and if it
              names one of Firefight&apos;s it becomes your copy of it.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 py-4">
            <Label htmlFor="skill-import-file">File</Label>
            <Input id="skill-import-file" type="file" accept=".md,text/markdown,text/plain" onChange={choose} aria-invalid={Boolean(errors.file)} />
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
