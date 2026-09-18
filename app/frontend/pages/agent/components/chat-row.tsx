import { Link } from "@inertiajs/react"
import { IconMessage, IconPinFilled } from "@tabler/icons-react"

import { agentChatPath } from "@/lib/routes"
import { ChatRowActions } from "@/pages/agent/components/chat-row-actions"
import { clockTime } from "@/pages/agent/lib/format-time"
import type { AgentChat } from "@/types/serializers"

interface ChatRowProps {
  chat: AgentChat
  current: boolean
}

// The menu sits beside the link rather than inside it, so opening it never opens the chat too. It
// takes the time's place while the row is hovered or the menu has focus.
export function ChatRow({ chat, current }: ChatRowProps) {
  return (
    <div
      className={`group relative rounded-control transition-colors duration-100 ${
        current ? "bg-hover-2" : "hover:bg-hover"
      }`}
    >
      <Link href={agentChatPath(chat.id)} className="flex gap-2.5 px-2.5 py-2">
        <span className="mt-0.5 shrink-0 text-ink-3">
          {chat.pinned ? <IconPinFilled className="size-3.5" /> : <IconMessage className="size-3.5" />}
        </span>
        <span className="min-w-0 flex-1">
          <span className="flex items-baseline justify-between gap-2">
            <span className="truncate text-[12.5px] text-ink">{chat.title}</span>
            <span className="shrink-0 font-mono text-[11px] text-ink-3 tabular-nums transition-opacity duration-100 group-focus-within:opacity-0 group-hover:opacity-0">
              {clockTime(chat.updatedAt)}
            </span>
          </span>
          {chat.preview.length > 0 && (
            <span className="mt-0.5 block truncate pr-6 text-[12px] text-ink-3">{chat.preview}</span>
          )}
        </span>
      </Link>
      <ChatRowActions
        chat={chat}
        className="absolute top-1.5 right-1.5 opacity-0 group-focus-within:opacity-100 group-hover:opacity-100 data-[state=open]:opacity-100"
      />
    </div>
  )
}
