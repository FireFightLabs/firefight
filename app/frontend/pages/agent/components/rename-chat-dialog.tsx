import { type FormEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { whenClosed } from "@/lib/handlers"

interface RenameChatDialogProps {
  chatId: string
  open: boolean
  title: string
  onRename: (title: string) => void
  onCancel: () => void
}

export function RenameChatDialog({ chatId, open, title, onRename, onCancel }: RenameChatDialogProps) {
  return (
    <Dialog open={open} onOpenChange={whenClosed(onCancel)}>
      <DialogContent className="sm:max-w-md">
        <RenameChatForm chatId={chatId} title={title} onRename={onRename} onCancel={onCancel} />
      </DialogContent>
    </Dialog>
  )
}

// Mounted only while the dialog is open, so every opening starts from the chat's current name.
function RenameChatForm({ chatId, title, onRename, onCancel }: Omit<RenameChatDialogProps, "open">) {
  const [ draft, setDraft ] = useState(title)
  const fieldId = `chat-title-${chatId}`
  const blank = draft.trim().length === 0

  function save(event: FormEvent) {
    event.preventDefault()
    if (blank) {
      return
    }

    onRename(draft.trim())
  }

  return (
    <form onSubmit={save}>
      <DialogHeader>
        <DialogTitle>Rename chat</DialogTitle>
        <DialogDescription>A chat is named after its first question until you rename it.</DialogDescription>
      </DialogHeader>
      <div className="flex flex-col gap-2 py-4">
        <Label htmlFor={fieldId}>Name</Label>
        <Input id={fieldId} value={draft} onChange={(event) => setDraft(event.target.value)} autoFocus />
      </div>
      <DialogFooter>
        <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
        <Button type="submit" disabled={blank}>Rename</Button>
      </DialogFooter>
    </form>
  )
}
