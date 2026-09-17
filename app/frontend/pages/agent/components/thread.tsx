import { useEffect, useRef } from "react"

import { AGENT_STEP_STATUSES } from "@/lib/generated/constants"
import { Message } from "@/pages/agent/components/message"
import { ToolRow } from "@/pages/agent/components/tool-row"
import type { AgentStream } from "@/pages/agent/hooks/use-agent-stream"
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
      <div className="flex flex-1 items-center justify-center rounded-window bg-surface shadow-card">
        <p className="max-w-sm text-center text-[13px] text-ink-2">
          Ask about an incident, what changed recently, or whether this has happened before. Start a
          chat on the left.
        </p>
      </div>
    )
  }

  const waiting = stream.state === "working" && stream.text.length === 0

  return (
    <div className="min-h-0 flex-1 overflow-y-auto rounded-window bg-surface p-4 shadow-card">
      <div className="mx-auto flex max-w-2xl flex-col gap-4">
        {messages.map((message) => (
          <Message key={message.id} message={message} />
        ))}
        {(stream.steps.length > 0 || stream.text.length > 0) && (
          <div className="flex flex-col gap-1">
            {stream.steps.map((step) => (
              <ToolRow key={step.key} name={step.title} answered={step.status === AGENT_STEP_STATUSES.DONE} />
            ))}
            {stream.text.length > 0 && (
              <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed text-ink">{stream.text}</p>
            )}
          </div>
        )}
        {waiting && <p className="animate-pulse text-[12.5px] text-ink-3">Working…</p>}
        <div ref={foot} />
      </div>
    </div>
  )
}
