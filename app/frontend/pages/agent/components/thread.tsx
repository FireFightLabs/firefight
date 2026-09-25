import { useEffect, useMemo, useRef } from "react"

import LoadingState from "@/components/agent-ui/loading-state"
import { ConfirmCard } from "@/pages/agent/components/confirm-card"
import { Message } from "@/pages/agent/components/message"
import { groupedTurns, liveTurn, settledMessages } from "@/pages/agent/lib/group-turns"
import type { AgentStream } from "@/pages/agent/types"
import type { AgentChatConfirmation, AgentChatMessage, AgentChatWaitingMessage } from "@/types/serializers"

interface ThreadProps {
  conversationId: string | null
  confirmations: AgentChatConfirmation[]
  messages: AgentChatMessage[]
  waiting: AgentChatWaitingMessage[]
  stream: AgentStream
}

export function Thread({ conversationId, confirmations, messages, waiting, stream }: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)
  const turns = useMemo(() => groupedTurns(settledMessages(messages, stream.owed)), [ messages, stream.owed ])
  const live = liveTurn(stream, messages)

  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" })
  }, [ messages.length, waiting.length, stream.text, stream.steps.length ])

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-8">
      <div className="mx-auto flex max-w-3xl flex-col gap-8">
        {turns.map((turn) => (
          <Message key={turn.id} turn={turn} />
        ))}
        {live && <Message turn={live} />}
        {stream.busy && stream.text.length === 0 && <LoadingState label="Working" />}
        {waiting.map((message) => (
          <WaitingMessage key={message.id} body={message.body} />
        ))}
        {conversationId && confirmations.length > 0 && !stream.busy && (
          <ConfirmCard conversationId={conversationId} confirmations={confirmations} />
        )}
        <div ref={foot} />
      </div>
    </div>
  )
}

// Sent while the agent works. It joins the answer at the agent's next step, and until then it says so.
function WaitingMessage({ body }: { body: string }) {
  return (
    <div className="flex flex-col items-end gap-1">
      <p className="max-w-[75%] whitespace-pre-wrap rounded-[18px] bg-accent-tint px-4 py-2 text-[14px] leading-relaxed text-ink opacity-70">
        {body}
      </p>
      <span className="text-[12px] text-ink-3">Halon reads this at its next step</span>
    </div>
  )
}
