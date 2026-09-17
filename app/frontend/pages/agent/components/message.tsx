import { CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { AgentSteps } from "@/pages/agent/components/agent-steps"
import type { AgentChatMessage } from "@/types/serializers"

interface MessageProps {
  message: AgentChatMessage
}

export function Message({ message }: MessageProps) {
  if (message.role === CHAT_MESSAGE_ROLES.USER) {
    return (
      <p className="self-end rounded-card bg-accent-tint px-3 py-2 text-[13.5px] text-ink">{message.body}</p>
    )
  }

  return (
    <div className="flex flex-col gap-2">
      {message.tools.length > 0 && <AgentSteps steps={message.tools} />}
      {message.body.trim().length > 0 && (
        <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed text-ink">{message.body}</p>
      )}
    </div>
  )
}
