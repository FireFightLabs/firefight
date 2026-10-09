import { useForm } from "@inertiajs/react"
import type { FormEvent } from "react"

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
import { CHAT_MEMORY_TEXT_LIMIT } from "@/lib/generated/constants"
import { correctMemoryPath, rejectMemoryPath } from "@/lib/routes"
import { TextField } from "@/components/memory/text-field"

// The memory deciding is about, from the Memory page or a card in a chat.
export interface DecidedMemory {
  id: string
  text: string
}

export const DECISIONS = { CORRECT: "correct", REJECT: "reject" } as const
export type Decision = (typeof DECISIONS)[keyof typeof DECISIONS]

interface DecideMemoryDialogProps {
  memory: DecidedMemory | null
  decision: Decision
  onClose: () => void
}

const COPY: Record<Decision, { title: string; description: string; submit: string }> = {
  correct: {
    title: "Correct this memory",
    description: "Write what is true instead. Halon keeps the old wording as rejected so it never learns it again, and uses your correction as confirmed by you.",
    submit: "Save correction",
  },
  reject: {
    title: "Mark as not right",
    description: "Halon stops using it and will not learn it again from a later incident.",
    submit: "Mark as not right",
  },
}

// Correcting and rejecting both retire the memory, and correcting also writes what replaces it.
export function DecideMemoryDialog({ memory, decision, onClose }: DecideMemoryDialogProps) {
  const { data, setData, post, processing } = useForm({ text: memory?.text ?? "", reason: "" })
  const copy = COPY[decision]
  const correcting = decision === DECISIONS.CORRECT
  const text = data.text.trim()
  const unchanged = correcting && text === memory?.text.trim()
  const invalid = correcting ? text.length === 0 || text.length > CHAT_MEMORY_TEXT_LIMIT || unchanged : false

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!memory) {
      return
    }
    post(correcting ? correctMemoryPath(memory.id) : rejectMemoryPath(memory.id), { preserveScroll: true, preserveState: true, onSuccess: onClose })
  }

  function writeText(value: string) {
    setData("text", value)
  }

  function writeReason(value: string) {
    setData("reason", value)
  }

  function changeOpen(open: boolean) {
    if (!open) {
      onClose()
    }
  }

  return (
    <Dialog open={memory !== null} onOpenChange={changeOpen}>
      <DialogContent>
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>{copy.title}</DialogTitle>
            <DialogDescription>{copy.description}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 pt-3 pb-5">
            {!correcting && memory && <blockquote className="edge-bar rounded-lg bg-muted/40 px-3 py-2 [--edge-bar:var(--border-strong)] text-sm">{memory.text}</blockquote>}
            {correcting && <TextField id="memory-correction" label="What is true" value={data.text} limit={CHAT_MEMORY_TEXT_LIMIT} onChange={writeText} />}
            <TextField
              id="memory-reason"
              label="Why"
              optional
              rows={2}
              value={data.reason}
              placeholder={correcting ? "Such as: we moved off the replica in March" : "Such as: that was a one off during the migration"}
              onChange={writeReason}
            />
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" variant={correcting ? "default" : "destructive"} disabled={processing || invalid}>
              {processing ? "Saving…" : copy.submit}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
