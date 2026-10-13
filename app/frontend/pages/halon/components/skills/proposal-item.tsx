import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconSparkles } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { SkillContentDiff } from "@/components/skills/skill-content-diff"
import { Button } from "@/components/ui/button"
import { formatDate } from "@/lib/formatters"
import { acceptHalonSkillProposalPath, dismissHalonSkillProposalPath } from "@/lib/routes"
import type { HalonSkillProposal } from "@/types/serializers"

interface ProposalItemProps {
  proposal: HalonSkillProposal
  canDecide: boolean
  onEdit: (proposal: HalonSkillProposal) => void
}

function headingFor(proposal: HalonSkillProposal): string {
  if (proposal.newSkill && proposal.copyOf) {
    return "A change to one of Firefight's skills, as your copy"
  }
  return proposal.newSkill ? "New skill proposed by Halon" : "Change proposed by Halon"
}

// A skill Halon proposed, beside what the skill says now, with why. Accept makes it live as written, Edit first changes
// it before it goes live, and Dismiss leaves the skills as they are.
export function ProposalItem({ proposal, canDecide, onEdit }: ProposalItemProps) {
  const [ sending, setSending ] = useState(false)

  function doneSending() {
    setSending(false)
  }

  function accept() {
    setSending(true)
    router.post(acceptHalonSkillProposalPath(proposal.id), {}, { preserveScroll: true, onFinish: doneSending })
  }

  function dismiss() {
    setSending(true)
    router.post(dismissHalonSkillProposalPath(proposal.id), {}, { preserveScroll: true, onFinish: doneSending })
  }

  function edit() {
    onEdit(proposal)
  }

  return (
    <article className="flex flex-col gap-4 border-b px-6 py-5 last:border-b-0">
      <header className="flex flex-col gap-2">
        <div className="flex items-center gap-2 text-xs font-medium text-brand">
          <IconSparkles className="size-4" />
          {headingFor(proposal)}
        </div>
        <h3 className="font-mono text-base font-semibold text-fg-headline [overflow-wrap:anywhere]">{proposal.name}</h3>
        <p className="text-xs text-muted-foreground">From {proposal.origin}, {formatDate(proposal.at)}</p>
        <div className="rounded-md border bg-surface-card px-3 py-2.5">
          <p className="text-xs font-medium text-muted-foreground">Why</p>
          <p className="mt-1 text-sm text-fg-body">{proposal.reason}</p>
        </div>
        {canDecide && (
          <div className="flex flex-wrap items-center gap-2">
            <Blocked reason={proposal.acceptBlockedReason} side="top">
              <Button type="button" size="sm" disabled={Boolean(proposal.acceptBlockedReason) || sending} onClick={accept}>
                {proposal.newSkill ? "Add skill" : "Accept change"}
              </Button>
            </Blocked>
            <Button type="button" size="sm" variant="outline" disabled={sending} onClick={edit}>Edit first</Button>
            <Button type="button" size="sm" variant="ghost" disabled={sending} onClick={dismiss}>Dismiss</Button>
          </div>
        )}
      </header>
      <SkillContentDiff before={proposal.current} after={proposal.proposed} beforeLabel="It says now" afterLabel="Halon would make it say" />
    </article>
  )
}
