import { useState, type ChangeEvent, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import type { Errors } from "@inertiajs/core"

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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { FormErrors } from "@/components/form-errors"
import { whenClosed } from "@/lib/handlers"
import { aiAccountPath } from "@/lib/routes"
import type { WorkspaceAiAccount } from "@/types/serializers"

interface Draft {
  label: string
  main: string
  fast: string
}

function draftFor(account: WorkspaceAiAccount | null): Draft {
  return { label: account?.label ?? "", main: account?.models.main ?? "", fast: account?.models.fast ?? "" }
}

// A connected subscription's name and the models Halon runs on, chosen from those its sign-in serves. The sign-in
// itself is changed by signing in again, never here.
export function SubscriptionAccountDialog({ account, onClose }: { account: WorkspaceAiAccount | null; onClose: () => void }) {
  const [draft, setDraft] = useState<Draft>(() => draftFor(account))
  const [errors, setErrors] = useState<Errors>({})
  const [processing, setProcessing] = useState(false)
  const [lastId, setLastId] = useState<string | null>(null)
  if (account && account.id !== lastId) {
    setLastId(account.id)
    setDraft(draftFor(account))
    setErrors({})
  }
  if (!account && lastId !== null) {
    setLastId(null)
  }

  const models = account?.subscription?.models ?? []

  function changeLabel(event: ChangeEvent<HTMLInputElement>) {
    setDraft({ ...draft, label: event.target.value })
  }

  function changeMain(value: string) {
    setDraft({ ...draft, main: value })
  }

  function changeFast(value: string) {
    setDraft({ ...draft, fast: value })
  }

  function finish() {
    setProcessing(false)
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    if (!account) {
      return
    }
    setProcessing(true)
    router.patch(
      aiAccountPath(account.id),
      { label: draft.label, settings: {}, models: { main: draft.main, fast: draft.fast } },
      { preserveScroll: true, onSuccess: onClose, onError: setErrors, onFinish: finish },
    )
  }

  return (
    <Dialog open={Boolean(account)} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit {account?.label}</DialogTitle>
            <DialogDescription>
              Change its name or the models Halon uses it with. Saving checks the subscription again with one short call.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <FormErrors errors={errors} />
            <div className="flex flex-col gap-2">
              <Label htmlFor={`subscription-label-${account?.id ?? "none"}`}>Name</Label>
              <Input id={`subscription-label-${account?.id ?? "none"}`} value={draft.label} onChange={changeLabel} />
            </div>
            <div className="flex flex-col gap-2">
              <Label>Main model</Label>
              <Select value={draft.main} onValueChange={changeMain}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Choose a model" />
                </SelectTrigger>
                <SelectContent>
                  {models.map((model) => (
                    <SelectItem key={model.id} value={model.id}>{model.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">What Halon investigates and answers with.</p>
            </div>
            <div className="flex flex-col gap-2">
              <Label>Quick model</Label>
              <Select value={draft.fast} onValueChange={changeFast}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Choose a model" />
                </SelectTrigger>
                <SelectContent>
                  {models.map((model) => (
                    <SelectItem key={model.id} value={model.id}>{model.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <p className="text-xs text-muted-foreground">What Halon writes summaries and other short work with.</p>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={processing}>{processing ? "Saving" : "Save"}</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
