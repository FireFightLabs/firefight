import { useState } from "react"

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

interface RenameChatDialogProps {
  open: boolean
  title: string
  onRename: (title: string) => void
  onCancel: () => void
}

export function RenameChatDialog({ open, title, onRename, onCancel }: RenameChatDialogProps) {
  const [ draft, setDraft ] = useState(title)

  function save() {
    if (draft.trim().length === 0) {
      return
    }

    onRename(draft.trim())
  }

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onCancel()}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Rename chat</DialogTitle>
          <DialogDescription>A chat is named after the first question by default.</DialogDescription>
        </DialogHeader>
        <Input value={draft} onChange={(event) => setDraft(event.target.value)} autoFocus />
        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
          <Button type="button" onClick={save} disabled={draft.trim().length === 0}>Rename</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
