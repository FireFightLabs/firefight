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
import { incidentPostmortemAiRewritePath } from "@/lib/routes"

interface AiRewriteDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  incidentId: string
  selectedHtml: string
  onRewritten: (rewrittenHtml: string) => void
}

export function AiRewriteDialog({
  open,
  onOpenChange,
  incidentId,
  selectedHtml,
  onRewritten,
}: AiRewriteDialogProps) {
  const [instruction, setInstruction] = useState("")
  const [processing, setProcessing] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [prevOpen, setPrevOpen] = useState(open)
  if (open !== prevOpen) {
    setPrevOpen(open)
    if (open) {
      setInstruction("")
      setError(null)
    }
  }

  const handleSubmit = async (event: FormEvent) => {
    event.preventDefault()
    if (!instruction.trim()) return

    setProcessing(true)
    setError(null)

    const csrfToken = document
      .querySelector('meta[name="csrf-token"]')
      ?.getAttribute("content")

    try {
      const response = await fetch(incidentPostmortemAiRewritePath(incidentId), {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(csrfToken ? { "X-CSRF-Token": csrfToken } : {}),
        },
        body: JSON.stringify({ selected_html: selectedHtml, instruction }),
      })

      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        throw new Error(body.error || "Failed to rewrite")
      }

      const { rewritten_html } = await response.json()
      onRewritten(rewritten_html)
      onOpenChange(false)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to rewrite")
    } finally {
      setProcessing(false)
    }
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
            onChange={(e) => setInstruction(e.target.value)}
            placeholder="e.g. make this more concise, add a bulleted list of people involved, expand on the root cause..."
            disabled={processing}
          />
          {error && (
            <p className="text-xs text-destructive">{error}</p>
          )}
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" disabled={processing || !instruction.trim()}>
              {processing ? "Rewriting..." : "Rewrite"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
