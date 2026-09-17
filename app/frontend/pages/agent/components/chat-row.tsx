import { Link } from "@inertiajs/react"
import { IconMessage, IconPinFilled } from "@tabler/icons-react"

import { agentChatPath } from "@/lib/routes"
import { clockTime } from "@/pages/agent/lib/format-time"
import type { AgentChat } from "@/types/serializers"

interface ChatRowProps {
  chat: AgentChat
  current: boolean
}

export function ChatRow({ chat, current }: ChatRowProps) {
  return (
    <Link
      href={agentChatPath(chat.id)}
      className={`flex gap-2.5 rounded-control px-2.5 py-2 transition-colors duration-100 ${
        current ? "bg-hover-2" : "hover:bg-hover"
      }`}
    >
      <span className="mt-0.5 shrink-0 text-ink-3">
        {chat.pinned ? <IconPinFilled className="size-3.5" /> : <IconMessage className="size-3.5" />}
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-baseline justify-between gap-2">
          <span className="truncate text-[12.5px] text-ink">{chat.title}</span>
          <span className="shrink-0 font-mono text-[11px] text-ink-3 tabular-nums">
            {clockTime(chat.updatedAt)}
          </span>
        </span>
        {chat.preview.length > 0 && (
          <span className="mt-0.5 block truncate text-[12px] text-ink-3">{chat.preview}</span>
        )}
      </span>
    </Link>
  )
}
