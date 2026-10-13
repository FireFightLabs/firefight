import { useEffect, useMemo, useRef } from "react"

import { PersonBubble } from "@/components/agent-chat/person-bubble"
import { groupedTurns, liveTurn, settledMessages } from "@/lib/agent-chat/group-turns"
import type { AgentStream } from "@/lib/agent-chat/types"
import { ChatTurn } from "@/pages/halon/components/workflow/chat-turn"
import type { AgentChatMessage } from "@/types/serializers"

interface ChatTranscriptProps {
  messages: AgentChatMessage[]
  stream: AgentStream
  pending: string | null
  fullChatUrl: string | null
  onOpenImage: (attachmentId: string) => void
}

// What was said beside the canvas, newest at the bottom, kept in view as Halon answers.
export function ChatTranscript({ messages, stream, pending, fullChatUrl, onOpenImage }: ChatTranscriptProps) {
  const turns = useMemo(() => groupedTurns(settledMessages(messages, stream.owed)), [ messages, stream.owed ])
  const live = liveTurn(stream, messages)
  const end = useRef<HTMLDivElement>(null)

  useEffect(() => {
    end.current?.scrollIntoView({ block: "end" })
  }, [ turns.length, stream.text, stream.steps.length, pending ])

  return (
    <div className="flex flex-col gap-5 px-4 py-4">
      {turns.map((turn) => (
        <ChatTurn key={turn.id} turn={turn} fullChatUrl={fullChatUrl} onOpenImage={onOpenImage} />
      ))}
      {live && <ChatTurn turn={live} live fullChatUrl={fullChatUrl} onOpenImage={onOpenImage} />}
      {pending && <PersonBubble body={pending} attachments={[]} onOpenImage={onOpenImage} className="opacity-60" />}
      <div ref={end} />
    </div>
  )
}
