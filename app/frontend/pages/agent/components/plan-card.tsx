import { IconListCheck, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { CHAT_PLAN_ACTIONS, CHAT_PLAN_STATUSES } from "@/lib/generated/constants"
import { agentChatPlanCancelPath, agentChatPlanRetryPath, agentChatPlanSchedulePath, agentChatPlanUndoPath } from "@/lib/routes"
import { PlanLinks } from "@/pages/agent/components/plan-links"
import { PlanStep } from "@/pages/agent/components/plan-step"
import { sendPlanAction } from "@/pages/agent/lib/chat-updates"
import type { AgentChatPlan } from "@/types/serializers"

type PlanAction = AgentChatPlan["offers"][number]["action"]

interface PlanCardProps {
  conversationId: string
  plan: AgentChatPlan
}

const ACTIONS: Record<PlanAction, { label: string; variant: "primary" | "secondary"; path: (conversationId: string, planId: string) => string }> = {
  [CHAT_PLAN_ACTIONS.SCHEDULE]: { label: "Schedule", variant: "primary", path: agentChatPlanSchedulePath },
  [CHAT_PLAN_ACTIONS.RETRY]: { label: "Retry", variant: "primary", path: agentChatPlanRetryPath },
  [CHAT_PLAN_ACTIONS.UNDO]: { label: "Undo", variant: "secondary", path: agentChatPlanUndoPath },
  [CHAT_PLAN_ACTIONS.CANCEL]: { label: "Cancel plan", variant: "secondary", path: agentChatPlanCancelPath },
}

// These change what happens next, so they ask first. Schedule and Retry do not, since the card already shows the plan
// and every change in it still asks when it runs.
const CONFIRMS: Partial<Record<PlanAction, { title: string; description: string; confirmLabel: string }>> = {
  [CHAT_PLAN_ACTIONS.CANCEL]: {
    title: "Cancel this plan?",
    description: "Nothing in it will run. Halon can make a new plan when you ask.",
    confirmLabel: "Cancel plan",
  },
  [CHAT_PLAN_ACTIONS.UNDO]: {
    title: "Undo this plan?",
    description: "Halon puts back what the plan changed, newest first, from the undo each change was written with. Each change still asks you before it runs.",
    confirmLabel: "Undo plan",
  },
}

// A plan Halon keeps for a request that takes more than one step, as a checklist that moves while it works. It shows when
// it runs, each step as it stands, why it stopped, and how it ended with the pages that show it and the next step. The
// server ships what is offered and why each is blocked, so the card decides nothing.
export function PlanCard({ conversationId, plan }: PlanCardProps) {
  const [ sending, setSending ] = useState<PlanAction | null>(null)
  const [ confirming, setConfirming ] = useState<PlanAction | null>(null)
  const confirm = confirming ? CONFIRMS[confirming] : undefined
  const blocked = plan.offers.map((offer) => offer.blockedReason).find((reason) => reason != null)

  function send(action: PlanAction) {
    setSending(action)
    sendPlanAction(ACTIONS[action].path(conversationId, plan.id), { onFinish: doneSending })
  }

  function press(action: PlanAction) {
    if (CONFIRMS[action]) {
      setConfirming(action)
      return
    }
    send(action)
  }

  function confirmed() {
    if (confirming) {
      send(confirming)
    }
    setConfirming(null)
  }

  function cancelConfirm() {
    setConfirming(null)
  }

  function doneSending() {
    setSending(null)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Plan">
      <div className="flex items-start gap-2">
        <IconListCheck className="mt-0.5 size-4 shrink-0 text-ink-2" />
        <div className="flex min-w-0 flex-col gap-1">
          <p className="text-[12.5px] font-medium text-ink-2">{plan.heading}</p>
          <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{plan.goal}</h3>
          {plan.undoes && <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">Undoes: {plan.undoes}</p>}
          <p className="text-[12.5px] text-ink-3">{plan.progress}</p>
        </div>
      </div>
      <ol className="flex flex-col gap-1.5">
        {plan.steps.map((step) => (
          <PlanStep key={step.id} step={step} />
        ))}
      </ol>
      {plan.stopReason && <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{plan.stopReason}</p>}
      {plan.status === CHAT_PLAN_STATUSES.COMPLETED && <PlanOutcome plan={plan} />}
      {plan.offers.length > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          {plan.offers.map((offer) => (
            <Button
              key={offer.action}
              size="sm"
              variant={ACTIONS[offer.action].variant}
              disabled={offer.blockedReason != null || sending != null}
              onClick={() => press(offer.action)}
            >
              {sending === offer.action && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              {ACTIONS[offer.action].label}
            </Button>
          ))}
        </div>
      )}
      {blocked && <p className="text-[12.5px] text-ink-3">{blocked}</p>}
      <ConfirmDeleteDialog
        open={confirm != null}
        title={confirm?.title ?? ""}
        description={confirm?.description ?? ""}
        confirmLabel={confirm?.confirmLabel}
        confirmVariant={confirming === CHAT_PLAN_ACTIONS.UNDO ? "default" : "destructive"}
        onConfirm={confirmed}
        onCancel={cancelConfirm}
      />
    </section>
  )
}

// How a finished plan ended against its goal, the pages that show it, and what Halon would do next.
function PlanOutcome({ plan }: { plan: AgentChatPlan }) {
  return (
    <div className="flex flex-col gap-1.5 border-t border-line pt-3 [overflow-wrap:anywhere]">
      {plan.outcome && <p className="text-[13px] leading-relaxed text-ink">{plan.outcome}</p>}
      <PlanLinks links={plan.links} />
      {plan.nextStep && (
        <p className="text-[13px] leading-relaxed text-ink-2">
          <span className="font-medium text-ink">Next: </span>
          {plan.nextStep}
        </p>
      )}
    </div>
  )
}
