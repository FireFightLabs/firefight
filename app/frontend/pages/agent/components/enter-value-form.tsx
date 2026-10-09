import { IconLoader2 } from "@tabler/icons-react"
import { type ChangeEvent, type FormEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import { DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { fillSecretEntry } from "@/pages/agent/lib/chat-updates"
import type { SecretDialogProps } from "@/pages/agent/types"

// Mounted only while open, so the value never outlives the dialog.
export function EnterValueForm({ conversationId, entry, onClose }: Omit<SecretDialogProps, "open">) {
  const [ value, setValue ] = useState("")
  const [ sending, setSending ] = useState(false)
  const fieldId = `secret-value-${entry.id}`
  const blank = value.length === 0

  function save(event: FormEvent) {
    event.preventDefault()
    if (blank || sending) {
      return
    }

    setSending(true)
    fillSecretEntry(conversationId, entry.id, value, { onSuccess: settled, onFinish: stopSending })
  }

  function settled() {
    setValue("")
    onClose()
  }

  function stopSending() {
    setSending(false)
  }

  function typed(event: ChangeEvent<HTMLInputElement>) {
    setValue(event.target.value)
  }

  return (
    <form onSubmit={save}>
      <DialogHeader>
        <DialogTitle>{entry.headline}</DialogTitle>
        <DialogDescription>{entry.body}</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-2 py-4">
        <Label htmlFor={fieldId}>Value</Label>
        <Input
          id={fieldId}
          type="password"
          autoComplete="off"
          spellCheck={false}
          value={value}
          onChange={typed}
          autoFocus
        />
      </div>
      <DialogFooter>
        <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
        <Button type="submit" disabled={blank || sending}>
          {sending && <IconLoader2 className="size-4 motion-safe:animate-spin" />}
          Set value
        </Button>
      </DialogFooter>
    </form>
  )
}
