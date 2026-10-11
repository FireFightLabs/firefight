import { usePage } from "@inertiajs/react"
import { IconBulb, IconCircleCheck, IconCircleX, type Icon } from "@tabler/icons-react"

import { isKeyOf } from "@/components/investigations/labels"
import { TONE_CLASSES, type Tone } from "@/components/investigations/tone"
import type { ChatTheoryStatus } from "@/lib/generated/constants"
import type { AgentPageProps } from "@/pages/agent/types"
import type { ChatTheory } from "@/types/serializers"

// The same marks and colours as a run's theories, so a cause reads the same in a chat and on a run's page.
const MARKS: Record<ChatTheoryStatus, { icon: Icon; tone: Tone; label: string }> = {
  open: { icon: IconBulb, tone: "open", label: "Open" },
  confirmed: { icon: IconCircleCheck, tone: "success", label: "Confirmed" },
  ruled_out: { icon: IconCircleX, tone: "error", label: "Ruled out" },
}

function markOf(status: string) {
  return isKeyOf(MARKS, status) ? MARKS[status] : MARKS.open
}

function TheoryRow({ theory }: { theory: ChatTheory }) {
  const mark = markOf(theory.status)
  const StatusIcon = mark.icon

  return (
    <li className="flex gap-2.5">
      <span className={`mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full border ${TONE_CLASSES[mark.tone]}`}>
        <StatusIcon className="size-3" strokeWidth={1.75} />
      </span>
      <div className="flex min-w-0 flex-col gap-0.5">
        <span className="text-[11px] font-medium tracking-[0.12em] text-fg-muted uppercase">
          {theory.leading ? `${mark.label} · leading` : mark.label}
        </span>
        <span className="text-[13px] leading-snug text-fg-body">{theory.title}</span>
        {theory.evidence && <span className="text-[12px] leading-snug text-fg-muted">{theory.evidence}</span>}
      </div>
    </li>
  )
}

// Halon's theory board as it stands, under the step that last updated it, so older updates do not repeat it.
export function TheoryCard({ toolCallKey }: { toolCallKey: string }) {
  const { theories } = usePage<AgentPageProps>().props
  const board = (theories ?? []).filter((theory) => theory.toolCallId === toolCallKey)
  if (board.length === 0) {
    return null
  }

  return (
    <div className="flex flex-col gap-2 rounded-lg border border-border-subtle p-3">
      <span className="text-[12px] font-medium text-fg-secondary">Theories</span>
      <ul className="flex flex-col gap-2.5">
        {board.map((theory) => (
          <TheoryRow key={theory.id} theory={theory} />
        ))}
      </ul>
    </div>
  )
}
