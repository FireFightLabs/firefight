import { type Icon, IconCheck, IconCircleDashed, IconLoader2, IconMinus, IconX } from "@tabler/icons-react"

import { CHAT_PLAN_STEP_KINDS, CHAT_PLAN_STEP_STATUSES, CHAT_PLAN_VERDICTS } from "@/lib/generated/constants"
import { PlanLinks } from "@/pages/agent/components/plan-links"
import type { AgentChatPlan } from "@/types/serializers"

type PlanStep = AgentChatPlan["steps"][number]

const STEP_ICONS: Record<PlanStep["status"], { icon: Icon; className: string }> = {
  [CHAT_PLAN_STEP_STATUSES.NOT_STARTED]: { icon: IconCircleDashed, className: "text-ink-3" },
  [CHAT_PLAN_STEP_STATUSES.RUNNING]: { icon: IconLoader2, className: "text-ink-2 motion-safe:animate-spin" },
  [CHAT_PLAN_STEP_STATUSES.DONE]: { icon: IconCheck, className: "text-success" },
  [CHAT_PLAN_STEP_STATUSES.FAILED]: { icon: IconX, className: "text-danger" },
  [CHAT_PLAN_STEP_STATUSES.SKIPPED]: { icon: IconMinus, className: "text-ink-3" },
}

const VERDICTS: Record<NonNullable<PlanStep["verdict"]>, { label: string; className: string }> = {
  [CHAT_PLAN_VERDICTS.HELD]: { label: "Worked", className: "text-success" },
  [CHAT_PLAN_VERDICTS.NOT_HELD]: { label: "Did not work", className: "text-danger" },
  [CHAT_PLAN_VERDICTS.COULD_NOT_CHECK]: { label: "Could not check", className: "text-warning" },
}

// One step of a plan: how it stands, where it happens, what it said, and for a change how it is put back.
export function PlanStep({ step }: { step: PlanStep }) {
  const mark = STEP_ICONS[step.status]
  const Mark = mark.icon
  const verdict = step.verdict ? VERDICTS[step.verdict] : null
  const showUndo = step.kind === CHAT_PLAN_STEP_KINDS.CHANGE && step.undo != null

  return (
    <li className="flex items-start gap-2 text-[13px] leading-relaxed">
      <Mark className={`mt-1 size-3.5 shrink-0 ${mark.className}`} aria-label={step.status.replace("_", " ")} />
      <div className="flex min-w-0 flex-col gap-0.5 [overflow-wrap:anywhere]">
        <p>
          <span className="text-ink-3">{step.position}. </span>
          <span className="font-medium text-ink">{step.description}</span>
          {step.place && <span className="text-ink-2"> · {step.place}</span>}
          {verdict && <span className={`font-medium ${verdict.className}`}> · {verdict.label}</span>}
        </p>
        {step.tool && <p className="text-[12.5px] text-ink-3">Runs {step.tool}</p>}
        {step.note && <p className="text-ink-2">{step.note}</p>}
        {showUndo && <p className="text-[12.5px] text-ink-3">Undo: {step.undo}</p>}
        <PlanLinks links={step.links} />
      </div>
    </li>
  )
}
