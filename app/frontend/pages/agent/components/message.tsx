import { IconSparkles } from "@tabler/icons-react"

import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { clockTime } from "@/pages/agent/lib/format-time"
import type { ChatTurn } from "@/pages/agent/lib/group-turns"

interface MessageProps {
  turn: ChatTurn
}

export function Message({ turn }: MessageProps) {
  if (turn.kind === "person") {
    return (
      <div className="flex flex-col items-end gap-1">
        <p className="max-w-[80%] rounded-card bg-accent-tint px-3 py-2 text-[13.5px] text-ink">{turn.body}</p>
        <span className="text-[11.5px] text-ink-3">{clockTime(turn.at)}</span>
      </div>
    )
  }

  return (
    <div className="flex gap-2.5">
      <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-control bg-accent-tint text-accent-ink">
        <IconSparkles className="size-3.5" />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="text-[12px] font-medium text-ink-2">Agent</span>
        {turn.steps.length > 0 && <AgentSteps steps={turn.steps} />}
        {turn.bodies.map((body, index) => (
          <p
            key={index}
            className="w-fit max-w-full whitespace-pre-wrap rounded-card bg-surface px-3 py-2 text-[13.5px] leading-relaxed text-ink shadow-hairline"
          >
            {body}
          </p>
        ))}
        {turn.at && <span className="text-[11.5px] text-ink-3">{clockTime(turn.at)}</span>}
      </div>
    </div>
  )
}
