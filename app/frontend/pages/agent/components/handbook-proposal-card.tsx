import { router } from "@inertiajs/react"
import { IconBook, IconCheck, IconExternalLink, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { Blocked } from "@/components/blocked-tooltip"
import { EditProposalDialog } from "@/components/handbook/edit-proposal-dialog"
import { WordingDiff } from "@/components/handbook/wording-diff"
import { MarkdownText } from "@/components/markdown-text"
import { HANDBOOK_PROPOSAL_QUERY } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { acceptHandbookProposalPath, dismissHandbookProposalPath, settingsHandbookPath } from "@/lib/routes"
import type { HandbookProposal } from "@/types/serializers"

interface HandbookProposalCardProps {
  proposal: HandbookProposal
}

const IN_PLACE = { preserveScroll: true, preserveState: true }
const NOT_YOURS = "Only people who may change the handbook can decide on this."
const CARD_TEXT = "text-[13px]! text-ink!"
const CARD_TEXT_MUTED = "text-[13px]! text-ink-3!"

// Something Halon read contradicted the handbook, so it proposes the edit while the person still has the context.
// Accept writes it as proposed, Edit changes it first, and Dismiss keeps the handbook as it is.
export function HandbookProposalCard({ proposal }: HandbookProposalCardProps) {
  const [ sending, setSending ] = useState(false)
  const [ editing, setEditing ] = useState(false)
  const canChange = useCan("handbook")
  const waiting = !proposal.decided
  const heading = proposal.newPage ? `Add ${proposal.pageTitle} to the handbook?` : `Update ${proposal.pageTitle} in the handbook?`
  const acceptBlocked = canChange ? proposal.acceptBlockedReason : NOT_YOURS
  const dismissBlocked = canChange ? proposal.dismissBlockedReason : NOT_YOURS

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
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Handbook edit">
      <div className="flex items-start gap-2">
        {proposal.decided ? <IconCheck className="mt-0.5 size-4 shrink-0 text-success" /> : <IconBook className="mt-0.5 size-4 shrink-0 text-warning" />}
        <h3 className="text-[14px] font-semibold leading-snug text-ink">{heading}</h3>
      </div>
      <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{proposal.evidence}</p>
      {waiting && !proposal.newPage && proposal.currentWording && (
        <div className="flex flex-col gap-1">
          <span className="text-[12px] text-ink-3">The page says now</span>
          <div className="max-h-48 overflow-y-auto [overflow-wrap:anywhere]">
            <WordingDiff before={proposal.currentWording} after={proposal.text} side="before" className={CARD_TEXT_MUTED} />
          </div>
        </div>
      )}
      <div className="flex flex-col gap-1">
        <span className="text-[12px] text-ink-3">{waiting ? "Halon would write" : "The page now says"}</span>
        <div className="max-h-64 overflow-y-auto [overflow-wrap:anywhere]">
          {waiting && !proposal.newPage && proposal.currentWording
            ? <WordingDiff before={proposal.currentWording} after={proposal.text} side="after" className={CARD_TEXT} />
            : <MarkdownText text={proposal.text} className={CARD_TEXT} />}
        </div>
      </div>
      {proposal.decided && <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">{proposal.decided}</p>}
      <div className="flex flex-wrap items-center gap-2">
        {waiting && (
          <>
            <Blocked reason={acceptBlocked} side="top">
              <Button size="sm" variant="primary" disabled={Boolean(acceptBlocked) || sending} onClick={accept}>
                {sending && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
                {proposal.newPage ? "Add page" : "Accept edit"}
              </Button>
            </Blocked>
            <Blocked reason={acceptBlocked} side="top">
              <Button size="sm" disabled={Boolean(acceptBlocked) || sending} onClick={openEdit}>
                Edit first
              </Button>
            </Blocked>
            <Blocked reason={dismissBlocked} side="top">
              <Button size="sm" disabled={Boolean(dismissBlocked) || sending} onClick={dismiss}>
                Dismiss
              </Button>
            </Blocked>
          </>
        )}
        <a href={settingsHandbookPath({ [HANDBOOK_PROPOSAL_QUERY]: proposal.id })} className="flex items-center gap-1 text-[12.5px] font-medium text-ink-2 hover:text-ink">
          <IconExternalLink className="size-3.5" />
          Open the handbook
        </a>
      </div>
      <EditProposalDialog key={editing ? "editing" : "closed"} proposal={editing ? proposal : null} onClose={closeEdit} />
    </section>
  )
}

export function HandbookProposals({ proposals }: { proposals: HandbookProposal[] | undefined }) {
  return proposals?.map((proposal) => <HandbookProposalCard key={proposal.id} proposal={proposal} />)
}
