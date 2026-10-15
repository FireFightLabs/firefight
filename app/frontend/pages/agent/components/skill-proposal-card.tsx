import { router } from "@inertiajs/react"
import { IconCheck, IconExternalLink, IconLoader2, IconSparkles } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { Blocked } from "@/components/blocked-tooltip"
import { SkillContentDiff } from "@/components/skills/skill-content-diff"
import { SKILL_PAGE_QUERIES } from "@/lib/generated/constants"
import { useCan } from "@/lib/permissions"
import { acceptHalonSkillProposalPath, dismissHalonSkillProposalPath, halonSkillsPath } from "@/lib/routes"
import { SHOWN_IN_PLACE, SKILL_PROPOSALS } from "@/pages/agent/lib/chat-updates"
import type { HalonSkillProposal } from "@/types/serializers"

interface SkillProposalCardProps {
  proposal: HalonSkillProposal
}

const NOT_YOURS = "Only people who may change the workspace's skills can decide on this."

function headingFor(proposal: HalonSkillProposal): string {
  if (proposal.newSkill && proposal.copyOf) {
    return `Make your own ${proposal.name}?`
  }
  return proposal.newSkill ? `Add the skill ${proposal.name}?` : `Change the skill ${proposal.name}?`
}

// A skill Halon proposed while the person still has the context. Accept makes it live as written, the Skills page edits
// it first, and Dismiss keeps the skills as they are.
export function SkillProposalCard({ proposal }: SkillProposalCardProps) {
  const [ sending, setSending ] = useState(false)
  const canChange = useCan("skills")
  const waiting = proposal.open
  const acceptBlocked = canChange ? proposal.acceptBlockedReason : NOT_YOURS
  const dismissBlocked = canChange ? undefined : NOT_YOURS

  function doneSending() {
    setSending(false)
  }

  function accept() {
    setSending(true)
    router.post(acceptHalonSkillProposalPath(proposal.id), {}, { ...SHOWN_IN_PLACE, only: SKILL_PROPOSALS, onFinish: doneSending })
  }

  function dismiss() {
    setSending(true)
    router.post(dismissHalonSkillProposalPath(proposal.id), {}, { ...SHOWN_IN_PLACE, only: SKILL_PROPOSALS, onFinish: doneSending })
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Proposed skill">
      <div className="flex items-start gap-2">
        {waiting ? <IconSparkles className="mt-0.5 size-4 shrink-0 text-warning" /> : <IconCheck className="mt-0.5 size-4 shrink-0 text-success" />}
        <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{headingFor(proposal)}</h3>
      </div>
      <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{proposal.reason}</p>
      {waiting && (
        <div className="max-h-80 overflow-y-auto">
          <SkillContentDiff
            before={proposal.current}
            after={proposal.proposed}
            beforeLabel="It says now"
            afterLabel="Halon would make it say"
            textClassName="text-[13px]! text-ink!"
            labelClassName="text-[12px] font-normal text-ink-3"
          />
        </div>
      )}
      {proposal.decided && <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">{proposal.decided}</p>}
      <div className="flex flex-wrap items-center gap-2">
        {waiting && (
          <>
            <Blocked reason={acceptBlocked} side="top">
              <Button size="sm" variant="primary" disabled={Boolean(acceptBlocked) || sending} onClick={accept}>
                {sending && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
                {proposal.newSkill ? "Add skill" : "Accept change"}
              </Button>
            </Blocked>
            <Blocked reason={dismissBlocked} side="top">
              <Button size="sm" disabled={Boolean(dismissBlocked) || sending} onClick={dismiss}>
                Dismiss
              </Button>
            </Blocked>
          </>
        )}
        <a
          href={halonSkillsPath(waiting ? { [SKILL_PAGE_QUERIES.PROPOSAL]: proposal.id } : {})}
          className="flex items-center gap-1 text-[12.5px] font-medium text-ink-2 hover:text-ink"
        >
          <IconExternalLink className="size-3.5" />
          {waiting && canChange ? "Edit it on the Skills page" : "Open Skills"}
        </a>
      </div>
    </section>
  )
}

export function SkillProposals({ proposals }: { proposals: HalonSkillProposal[] | undefined }) {
  return proposals?.map((proposal) => <SkillProposalCard key={proposal.id} proposal={proposal} />)
}
