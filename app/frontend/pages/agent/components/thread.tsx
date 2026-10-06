import { useEffect, useMemo, useRef, useState } from "react"

import LoadingState from "@/components/agent-ui/loading-state"
import { whenClosed } from "@/lib/handlers"
import { ConfirmCard } from "@/pages/agent/components/confirm-card"
import { ImageDialog } from "@/pages/agent/components/image-dialog"
import { Message } from "@/pages/agent/components/message"
import { MessageAttachments } from "@/pages/agent/components/message-attachments"
import { groupedTurns, liveTurn, settledMessages } from "@/pages/agent/lib/group-turns"
import { type AgentStream, type ChatTurn, TURN_KINDS } from "@/pages/agent/types"
import type { AgentChatAttachment, AgentChatConfirmation, AgentChatMessage, AgentChatWaitingMessage, ChatCompaction } from "@/types/serializers"

interface ThreadProps {
  conversationId: string | null
  confirmations: AgentChatConfirmation[]
  messages: AgentChatMessage[]
  compactions: ChatCompaction[]
  waiting: AgentChatWaitingMessage[]
  stream: AgentStream
}

export function Thread({ conversationId, confirmations, messages, compactions, waiting, stream }: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)
  const turns = useMemo(() => groupedTurns(settledMessages(messages, stream.owed), compactions), [ messages, compactions, stream.owed ])
  const live = liveTurn(stream, messages, compactions)
  // Held by id rather than by the message, which the server's copy replaces once it answers.
  const [ openImageId, setOpenImageId ] = useState<string | null>(null)
  const openImage = sentAttachments(turns, waiting).find((attachment) => attachment.id === openImageId) ?? null

  function closeImage() {
    setOpenImageId(null)
  }

  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" })
  }, [ messages.length, waiting.length, stream.text, stream.steps.length ])

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-8 [mask-image:linear-gradient(to_bottom,transparent,black_16px,black_calc(100%-32px),transparent)] [scrollbar-color:var(--line-strong)_transparent] [scrollbar-width:thin]">
      <div className="mx-auto flex max-w-3xl flex-col gap-8">
        {turns.map((turn) => (
          <Message key={turn.id} turn={turn} onOpenImage={setOpenImageId} />
        ))}
        {live && <Message turn={live} live onOpenImage={setOpenImageId} />}
        {stream.busy && stream.text.length === 0 && <LoadingState label="Working" />}
        {waiting.map((message) => (
          <WaitingMessage key={message.id} body={message.body} attachments={message.attachments} onOpenImage={setOpenImageId} />
        ))}
        {conversationId && confirmations.length > 0 && !stream.busy && (
          <ConfirmCard conversationId={conversationId} confirmations={confirmations} />
        )}
        <div ref={foot} />
      </div>
      <ImageDialog image={openImage} onOpenChange={whenClosed(closeImage)} />
    </div>
  )
}

function sentAttachments(turns: ChatTurn[], waiting: AgentChatWaitingMessage[]): AgentChatAttachment[] {
  const asked = turns.flatMap((turn) => (turn.kind === TURN_KINDS.PERSON ? turn.attachments : []))
  return [ ...asked, ...waiting.flatMap((message) => message.attachments) ]
}

interface WaitingMessageProps {
  body: string
  attachments: AgentChatAttachment[]
  onOpenImage: (attachmentId: string) => void
}

// Sent while the agent works. It joins the answer at the agent's next step, and until then it says so.
function WaitingMessage({ body, attachments, onOpenImage }: WaitingMessageProps) {
  return (
    <div className="flex flex-col items-end gap-1">
      {attachments.length > 0 && <MessageAttachments attachments={attachments} onOpenImage={onOpenImage} />}
      {body.length > 0 && (
        <p className="max-w-[85%] whitespace-pre-wrap rounded-[18px] rounded-br-md border border-border bg-surface-selected px-4 py-2.5 text-[14px] leading-relaxed text-ink opacity-70 [overflow-wrap:anywhere] sm:max-w-[75%]">
          {body}
        </p>
      )}
      <span className="text-[12px] text-ink-3">Halon reads this at its next step</span>
    </div>
  )
}
