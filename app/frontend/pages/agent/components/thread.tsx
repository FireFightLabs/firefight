import { useEffect, useRef } from "react"

import LoadingState from "@/components/agent-ui/loading-state"
import { Message } from "@/pages/agent/components/message"
import type { AgentStream } from "@/pages/agent/hooks/use-agent-stream"
import { groupedTurns } from "@/pages/agent/lib/group-turns"
import type { AgentChatMessage } from "@/types/serializers"

interface ThreadProps {
  messages: AgentChatMessage[]
  stream: AgentStream
  empty: boolean
}

export function Thread({ messages, stream, empty }: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)

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

  const waiting = stream.state === "working" && stream.text.length === 0

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-8">
      <div className="mx-auto flex max-w-3xl flex-col gap-8">
        {groupedTurns(messages).map((turn) => (
          <Message key={turn.id} turn={turn} />
        ))}
        {(stream.steps.length > 0 || stream.text.length > 0) && (
          <Message
            turn={{ kind: "agent", id: "live", steps: stream.steps, bodies: stream.text.length > 0 ? [ stream.text ] : [] }}
          />
        )}
        {waiting && <LoadingState label="Working" />}
        <div ref={foot} />
      </div>
    </div>
  )
}
