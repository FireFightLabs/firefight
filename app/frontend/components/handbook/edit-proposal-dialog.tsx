import { useForm } from "@inertiajs/react"
import type { FormEvent } from "react"

import { MarkdownEditor } from "@/components/markdown-editor"
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
import { whenClosed } from "@/lib/handlers"
import { HANDBOOK_TEXT_LIMIT } from "@/lib/generated/constants"
import { acceptHandbookProposalPath } from "@/lib/routes"
import type { HandbookProposal } from "@/types/serializers"

interface EditProposalDialogProps {
  proposal: HandbookProposal | null
  onClose: () => void
}

// Changes what Halon proposed before accepting it, from the Handbook page or the card in a chat.
export function EditProposalDialog({ proposal, onClose }: EditProposalDialogProps) {
  const { data, setData, post, processing } = useForm({ text: proposal?.text ?? "" })
  const text = data.text.trim()

  function submit(event: FormEvent) {
    event.preventDefault()
    if (proposal) {
      post(acceptHandbookProposalPath(proposal.id), { preserveScroll: true, preserveState: true, onSuccess: onClose })
    }
  }

  function writeText(value: string) {
    setData("text", value)
  }

  return (
    <Dialog open={proposal !== null} onOpenChange={whenClosed(onClose)}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-3xl">
        <form onSubmit={submit}>
          <DialogHeader>
            <DialogTitle>Edit {proposal?.pageTitle} before {proposal?.newPage ? "adding it" : "accepting"}</DialogTitle>
            <DialogDescription>{proposal?.evidence}</DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-2 pt-3 pb-5">
            <MarkdownEditor id="handbook-proposal-text" value={data.text} onChange={writeText} allowSource minHeight="min-h-72" />
            {!proposal?.newPage && <p className="text-xs text-muted-foreground">The page's current wording is kept as history.</p>}
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button type="button" variant="outline" size="sm" disabled={processing}>
                Cancel
              </Button>
            </DialogClose>
            <Button type="submit" size="sm" disabled={processing || text.length === 0 || data.text.length > HANDBOOK_TEXT_LIMIT}>
              {processing ? "Saving…" : proposal?.newPage ? "Add page" : "Accept with edit"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
