import { useEffect, useMemo, useRef } from "react"

import LoadingState from "@/components/agent-ui/loading-state"
import { Message } from "@/pages/agent/components/message"
import { groupedTurns, liveTurn } from "@/pages/agent/lib/group-turns"
import type { AgentStream } from "@/pages/agent/types"
import type { AgentChatMessage } from "@/types/serializers"

interface ThreadProps {
  messages: AgentChatMessage[]
  stream: AgentStream
  empty: boolean
}

export function Thread({ messages, stream, empty }: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)
  const turns = useMemo(() => groupedTurns(messages), [ messages ])
  const live = liveTurn(stream)

  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" })
  }, [ messages.length, stream.text, stream.steps.length ])

  if (empty) {
    return (
      <div className="flex flex-1 items-center justify-center">
        <p className="max-w-sm text-center text-[13px] text-ink-2">
          Ask about an incident, what changed recently, or whether this has happened before.
        </p>
      </div>
    )
  }

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-8">
      <div className="mx-auto flex max-w-3xl flex-col gap-8">
        {turns.map((turn) => (
          <Message key={turn.id} turn={turn} />
        ))}
        {live && <Message turn={live} />}
        {stream.busy && stream.text.length === 0 && <LoadingState label="Working" />}
        <div ref={foot} />
      </div>
    </div>
  )
}
