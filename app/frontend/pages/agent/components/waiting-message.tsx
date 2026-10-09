import { PersonBubble } from "@/pages/agent/components/person-bubble"
import type { AgentChatAttachment } from "@/types/serializers"

interface WaitingMessageProps {
  body: string
  attachments: AgentChatAttachment[]
  onOpenImage: (attachmentId: string) => void
}

// Sent while the agent works. It joins the answer at the agent's next step, and until then it says so.
export function WaitingMessage({ body, attachments, onOpenImage }: WaitingMessageProps) {
  return (
    <PersonBubble body={body} attachments={attachments} onOpenImage={onOpenImage} className="opacity-70">
      <span className="text-[12px] text-ink-3">Halon reads this at its next step</span>
    </PersonBubble>
  )
}
