import { usePage } from "@inertiajs/react"

import ThinkingState, { type ThinkingRow } from "@/components/agent-ui/thinking-state"
import { stepsWord } from "@/lib/code-fix-work"
import { HELPER_STATUSES } from "@/lib/generated/constants"
import { StepOutcomeDetails } from "@/pages/agent/components/step-outcome"
import { rowStatus } from "@/pages/agent/lib/step-rows"
import type { AgentPageProps } from "@/pages/agent/types"
import type { AgentChatHelper } from "@/types/serializers"

interface HelperRunsProps {
  // The run_helpers call the helpers came from.
  toolCallKey: string
}

type HelperStep = AgentChatHelper["steps"][number]

const ENDED_WORDS: Record<AgentChatHelper["status"], string> = {
  [HELPER_STATUSES.RUNNING]: "Checking",
  [HELPER_STATUSES.REPORTED]: "Reported",
  [HELPER_STATUSES.FAILED]: "No report",
  [HELPER_STATUSES.STOPPED]: "Stopped",
}

// Before its first step a helper is reading its brief, which says so rather than drawing an empty trace.
const STARTING: ThinkingRow = { id: "starting", primary: "Reading the brief", quiet: true }

// The checks Halon handed to helpers, under the step that started them. Each is its own trace, collapsed unless opened,
// with what it reported, or why it has no report, always in view.
export function HelperRuns({ toolCallKey }: HelperRunsProps) {
  const { helpers } = usePage<AgentPageProps>().props
  const shown = (helpers ?? []).filter((helper) => helper.toolCallId === toolCallKey)
  if (shown.length === 0) {
    return null
  }

  return (
    <ul className="flex flex-col gap-2" aria-label="Helpers">
      {shown.map((helper) => (
        <HelperRun key={helper.id} helper={helper} />
      ))}
    </ul>
  )
}

function HelperRun({ helper }: { helper: AgentChatHelper }) {
  const running = helper.status === HELPER_STATUSES.RUNNING
  const said = helper.report ?? helper.endedBecause

  return (
    <li className="flex min-w-0 flex-col gap-0.5">
      <ThinkingState
        rows={running && helper.steps.length === 0 ? [ STARTING ] : helper.steps.map(toRow)}
        active={helper.title}
        done={`${helper.title} · ${ENDED_WORDS[helper.status]} · ${stepsWord(helper.steps.length)}`}
        working={running}
        open={false}
        icon={<span className="size-1.5 rounded-full bg-current" />}
      />
      {!running && said && (
        <p className={`m-0 ml-6 text-[12.5px] leading-5 whitespace-pre-line [overflow-wrap:anywhere] ${helper.report ? "text-ink-2" : "text-ink-3"}`}>
          {said}
        </p>
      )}
    </li>
  )
}

function toRow(step: HelperStep): ThinkingRow {
  return {
    id: step.key,
    primary: step.title,
    secondary: step.headline || undefined,
    status: rowStatus(step.status),
    details: step.asked.map(([ label, meta ]) => ({ label, meta })),
    outcome: step.outcome ? <StepOutcomeDetails outcome={step.outcome} /> : undefined,
  }
}
