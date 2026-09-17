import { IconSparkles } from "@tabler/icons-react"

import { CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { AgentSteps } from "@/pages/agent/components/agent-steps"
import { clockTime } from "@/pages/agent/lib/format-time"
import type { AgentChatMessage } from "@/types/serializers"

interface MessageProps {
  message: AgentChatMessage
}

export function Message({ message }: MessageProps) {
  if (message.role === CHAT_MESSAGE_ROLES.USER) {
    return (
      <div className="flex flex-col items-end gap-1">
        <p className="max-w-[80%] rounded-card bg-accent-tint px-3 py-2 text-[13.5px] text-ink">{message.body}</p>
        <span className="text-[11.5px] text-ink-3">{clockTime(message.at)}</span>
      </div>
    )
  }

  return (
    <div className="flex gap-2.5">
      <span className="mt-0.5 flex size-6 shrink-0 items-center justify-center rounded-control bg-accent-tint text-accent-ink">
        <IconSparkles className="size-3.5" />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <span className="text-[12px] font-medium text-ink-2">Agent</span>
        {message.tools.length > 0 && <AgentSteps steps={message.tools} />}
        {message.body.trim().length > 0 && (
          <p className="w-fit max-w-full whitespace-pre-wrap rounded-card bg-surface px-3 py-2 text-[13.5px] leading-relaxed text-ink shadow-hairline">
            {message.body}
          </p>
        )}
        <span className="text-[11.5px] text-ink-3">{clockTime(message.at)}</span>
      </div>
    </div>
  )
}
