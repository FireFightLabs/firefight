import { Link } from "@inertiajs/react"

import { agentChatPath } from "@/lib/routes"
import { ChatRowActions } from "@/pages/agent/components/chat-row-actions"
import { OPEN_CHAT_VISIT } from "@/pages/agent/lib/chat-updates"
import type { AgentChat } from "@/types/serializers"

interface ChatRowProps {
  chat: AgentChat
  current: boolean
}

// The menu sits beside the link, not inside it, so opening the menu never opens the chat.
export function ChatRow({ chat, current }: ChatRowProps) {
  const reveal = current ? "opacity-100" : "opacity-0 group-hover:opacity-100 group-focus-within:opacity-100"

  return (
    <div
      className={`group relative flex items-center rounded-control transition-[background-color,box-shadow] duration-150 ${
        current ? "bg-hover-2 shadow-[inset_2px_0_0_var(--lime)]" : "hover:bg-hover"
      }`}
    >
      <Link
        href={agentChatPath(chat.id)}
        {...OPEN_CHAT_VISIT}
        className={`min-w-0 flex-1 truncate rounded-control py-1.5 pr-8 pl-2.5 text-[13px] transition-colors duration-150 ${current ? "text-ink" : "text-ink-2 group-hover:text-ink"}`}
      >
        {chat.title}
      </Link>
      <ChatRowActions chat={chat} open={current} className={`absolute right-1 ${reveal} data-[state=open]:opacity-100`} />
    </div>
  )
}
