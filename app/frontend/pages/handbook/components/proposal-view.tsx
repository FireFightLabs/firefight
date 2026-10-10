import { router } from "@inertiajs/react"
import { IconSparkles } from "@tabler/icons-react"
import { useState } from "react"

import { Blocked } from "@/components/blocked-tooltip"
import { EditProposalDialog } from "@/components/handbook/edit-proposal-dialog"
import { WordingDiff } from "@/components/handbook/wording-diff"
import { MarkdownText } from "@/components/markdown-text"
import { Button } from "@/components/ui/button"
import { formatDate } from "@/lib/formatters"
import { acceptHandbookProposalPath, dismissHandbookProposalPath } from "@/lib/routes"
import type { HandbookProposal } from "@/types/serializers"

interface ProposalViewProps {
  proposal: HandbookProposal
  canDecide: boolean
}

const IN_PLACE = { preserveScroll: true }

// An edit or a new page Halon proposed, beside what the page says now, with what Halon read that led to it.
export function ProposalView({ proposal, canDecide }: ProposalViewProps) {
  const [ sending, setSending ] = useState(false)
  const [ editing, setEditing ] = useState(false)

  function doneSending() {
    setSending(false)
  }

  function accept() {
    setSending(true)
    router.post(acceptHandbookProposalPath(proposal.id), {}, { ...IN_PLACE, onFinish: doneSending })
  }

  function dismiss() {
    setSending(true)
    router.post(dismissHandbookProposalPath(proposal.id), {}, { ...IN_PLACE, onFinish: doneSending })
  }

  function openEdit() {
    setEditing(true)
  }

  function closeEdit() {
    setEditing(false)
  }

  return (
    <article className="flex flex-col gap-5">
      <header className="flex flex-col gap-3 border-b pb-4">
        <div className="flex items-center gap-2 text-xs font-medium text-brand">
          <IconSparkles className="size-4" />
          {proposal.newPage ? "New page proposed by Halon" : "Edit proposed by Halon"}
        </div>
        <h2 className="text-xl font-semibold tracking-tight text-fg-headline [overflow-wrap:anywhere]">{proposal.pageTitle}</h2>
        <p className="text-xs text-muted-foreground">From {proposal.origin}, {formatDate(proposal.at)}</p>
        <div className="rounded-md border bg-surface-card px-3 py-2.5">
          <p className="text-xs font-medium text-muted-foreground">Why</p>
          <p className="mt-1 text-sm text-fg-body">{proposal.evidence}</p>
        </div>
        {canDecide && (
          <div className="flex flex-wrap items-center gap-2">
            <Blocked reason={proposal.acceptBlockedReason} side="top">
              <Button type="button" size="sm" disabled={Boolean(proposal.acceptBlockedReason) || sending} onClick={accept}>
                {proposal.newPage ? "Add page" : "Accept edit"}
              </Button>
            </Blocked>
            <Blocked reason={proposal.acceptBlockedReason} side="top">
              <Button type="button" size="sm" variant="outline" disabled={Boolean(proposal.acceptBlockedReason) || sending} onClick={openEdit}>
                Edit first
              </Button>
            </Blocked>
            <Blocked reason={proposal.dismissBlockedReason} side="top">
              <Button type="button" size="sm" variant="ghost" disabled={Boolean(proposal.dismissBlockedReason) || sending} onClick={dismiss}>
                Dismiss
              </Button>
            </Blocked>
          </div>
        )}
      </header>
      <div className={proposal.newPage ? "" : "grid gap-6 lg:grid-cols-2"}>
        {!proposal.newPage && (
          <section className="flex min-w-0 flex-col gap-2">
            <h3 className="text-xs font-medium text-muted-foreground">The page says now</h3>
            {proposal.currentWording
              ? <WordingDiff before={proposal.currentWording} after={proposal.text} side="before" className="text-fg-muted" />
              : <p className="text-sm text-muted-foreground">Nothing yet.</p>}
          </section>
        )}
        <section className="flex min-w-0 flex-col gap-2">
          <h3 className="text-xs font-medium text-muted-foreground">{proposal.newPage ? "Halon would write" : "Halon would change it to"}</h3>
          {proposal.currentWording && !proposal.decided
            ? <WordingDiff before={proposal.currentWording} after={proposal.text} side="after" className="text-fg-body!" />
            : <MarkdownText text={proposal.text} className="text-fg-body!" />}
        </section>
      </div>
      <EditProposalDialog key={editing ? "editing" : "closed"} proposal={editing ? proposal : null} onClose={closeEdit} />
    </article>
  )
}
