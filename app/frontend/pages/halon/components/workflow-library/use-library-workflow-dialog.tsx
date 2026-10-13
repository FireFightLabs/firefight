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
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { whenClosed } from "@/lib/handlers"
import { omitErrors } from "@/lib/form-errors"
import { adoptHalonLibraryWorkflowPath } from "@/lib/routes"
import type { HalonLibraryWorkflow } from "@/types/serializers"

const FOLLOW = "follow"
const COPY = "copy"
type Choice = typeof FOLLOW | typeof COPY

interface UseLibraryWorkflowDialogProps {
  item: HalonLibraryWorkflow | null
  onClose: () => void
}

function messageOf(errors: Errors, field: string): string | undefined {
  const message = errors[field]
  return Array.isArray(message) ? message[0] : message
}

// Makes a workflow from one of Firefight's: as it is, moving with each new version Firefight ships, or as the
// workspace's own copy to change. Either starts as a draft, as every new workflow does.
export function UseLibraryWorkflowDialog({ item, onClose }: UseLibraryWorkflowDialogProps) {
  const [ name, setName ] = useState("")
  const [ choice, setChoice ] = useState<Choice>(FOLLOW)
  const [ errors, setErrors ] = useState<Errors>({})
  const [ processing, setProcessing ] = useState(false)
  const [ lastKey, setLastKey ] = useState<string | null>(null)
  if (item && item.key !== lastKey) {
    setLastKey(item.key)
    setName(item.usedBy.length > 0 ? "" : item.name)
    setChoice(FOLLOW)
    setErrors({})
  }

  function writeName(event: ChangeEvent<HTMLInputElement>) {
    setName(event.target.value)
  }

  function pick(value: string) {
    setChoice(value === COPY ? COPY : FOLLOW)
  }

  function showErrors(received: Errors) {
    setErrors(received)
  }

  function doneSending() {
    setProcessing(false)
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (!item) {
      return
    }
    setProcessing(true)
    router.post(adoptHalonLibraryWorkflowPath(item.key), { name, following: choice === FOLLOW }, {
      preserveScroll: true, onSuccess: onClose, onError: showErrors, onFinish: doneSending,
    })
  }

  return (
    <Dialog open={item !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Use {item?.name}</DialogTitle>
            <DialogDescription>It starts as a draft, and runs once someone publishes it.</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <FormErrors errors={omitErrors(errors, "name")} />
            <div className="flex flex-col gap-2">
              <Label htmlFor="library-workflow-name">Name</Label>
              <Input id="library-workflow-name" value={name} onChange={writeName} placeholder={item?.name} aria-invalid={Boolean(errors.name)} />
              {messageOf(errors, "name") && <p className="text-xs text-destructive">{messageOf(errors, "name")}</p>}
            </div>
            <RadioGroup value={choice} onValueChange={pick} className="gap-3">
              <label htmlFor="library-workflow-follow" className="flex cursor-pointer items-start gap-3 rounded-md border px-3 py-2.5">
                <RadioGroupItem id="library-workflow-follow" value={FOLLOW} className="mt-0.5" />
                <span className="flex flex-col gap-0.5">
                  <span className="text-sm font-medium">Use it as it is</span>
                  <span className="text-xs text-muted-foreground">
                    It moves with each new version Firefight ships. You can still change what starts it, such as its schedule.
                  </span>
                </span>
              </label>
              <label htmlFor="library-workflow-copy" className="flex cursor-pointer items-start gap-3 rounded-md border px-3 py-2.5">
                <RadioGroupItem id="library-workflow-copy" value={COPY} className="mt-0.5" />
                <span className="flex flex-col gap-0.5">
                  <span className="text-sm font-medium">Make it your own copy</span>
                  <span className="text-xs text-muted-foreground">
                    Change any step. You are told when Firefight ships a newer version, with what changed, and it is never changed for you.
                  </span>
                </span>
              </label>
            </RadioGroup>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>Make the draft</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
