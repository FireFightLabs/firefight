import { useState, type FormEvent } from "react"
import { IconSparkles } from "@tabler/icons-react"

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
import { Textarea } from "@/components/ui/textarea"

interface AiRewriteDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSubmit: (instruction: string) => void
}

export function AiRewriteDialog({ open, onOpenChange, onSubmit }: AiRewriteDialogProps) {
  const [instruction, setInstruction] = useState("")
  const [prevOpen, setPrevOpen] = useState(open)
  if (open !== prevOpen) {
    setPrevOpen(open)
    if (open) {
      setInstruction("")
    }
  }

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault()
    if (!instruction.trim()) {
      return
    }
    onSubmit(instruction.trim())
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <IconSparkles className="size-4 text-primary" />
            Rewrite with AI
          </DialogTitle>
          <DialogDescription>
            Tell the AI how to rewrite the selected text. It has access to the incident context (timeline, summary, actions).
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <Textarea
            autoFocus
            rows={4}
            value={instruction}
            onChange={(event) => setInstruction(event.target.value)}
            placeholder="e.g. make this more concise, add a bulleted list of people involved, expand on the root cause..."
          />
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline">
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" disabled={!instruction.trim()}>
              Rewrite
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
