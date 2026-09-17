import { useEffect, useRef } from "react"

import { ToolRow } from "@/pages/agent_chats/components/tool-row"
import type { TurnState } from "@/pages/agent_chats/hooks/use-live-messages"
import type { AgentChatMessage } from "@/types/serializers"

interface ThreadProps {
  messages: AgentChatMessage[]
  state: TurnState
  empty: boolean
}

export function Thread({ messages, state, empty }: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)

  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" })
  }, [ messages.length, state ])

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

  return (
    <div className="min-h-0 flex-1 overflow-y-auto rounded-window bg-surface p-4 shadow-card">
      <div className="mx-auto flex max-w-2xl flex-col gap-4">
        {messages.map((message) => (
          <Message key={message.id} message={message} />
        ))}
        {state === "working" && <p className="animate-pulse text-[12.5px] text-ink-3">Working…</p>}
        {state === "stalled" && (
          <p className="text-[12.5px] text-ink-2">The agent did not reply. Ask again.</p>
        )}
        <div ref={foot} />
      </div>
    </div>
  )
}

function Message({ message }: { message: AgentChatMessage }) {
  if (message.role === "user") {
    return (
      <p className="self-end rounded-card bg-accent-tint px-3 py-2 text-[13.5px] text-ink">{message.body}</p>
    )
  }

  return (
    <div className="flex flex-col gap-1">
      {message.tools.map((tool) => (
        <ToolRow key={tool.id} name={tool.name} answered={tool.answered} />
      ))}
      {message.body.trim().length > 0 && (
        <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed text-ink">{message.body}</p>
      )}
    </div>
  )
}
