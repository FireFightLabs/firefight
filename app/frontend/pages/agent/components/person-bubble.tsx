import type { ReactNode } from "react"

import { MessageAttachments } from "@/pages/agent/components/message-attachments"
import type { AgentChatAttachment } from "@/types/serializers"

interface PersonBubbleProps {
  body: string
  attachments: AgentChatAttachment[]
  onOpenImage: (attachmentId: string) => void
  // Extra classes on the bubble, such as a fade while it waits.
  className?: string
  // Drawn under the bubble.
  children?: ReactNode
}

// What a person said in the chat, its files above the words.
export function PersonBubble({ body, attachments, onOpenImage, className = "", children }: PersonBubbleProps) {
  return (
    <div className="flex flex-col items-end gap-1.5">
      {attachments.length > 0 && <MessageAttachments attachments={attachments} onOpenImage={onOpenImage} />}
      {body.length > 0 && (
        <p className={`max-w-[85%] self-end whitespace-pre-wrap rounded-[18px] rounded-br-md border border-border bg-surface-selected px-4 py-2.5 text-[14px] leading-relaxed text-ink [overflow-wrap:anywhere] sm:max-w-[75%] ${className}`}>
          {body}
        </p>
      )}
      {children}
    </div>
  )
}
