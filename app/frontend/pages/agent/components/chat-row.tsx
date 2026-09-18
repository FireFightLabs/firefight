import { Link } from "@inertiajs/react"

import { agentChatPath } from "@/lib/routes"
import { ChatRowActions } from "@/pages/agent/components/chat-row-actions"
import type { AgentChat } from "@/types/serializers"

interface ChatRowProps {
  chat: AgentChat
  current: boolean
}

// The menu sits beside the link rather than inside it, so opening it never opens the chat too. It is
// always there on the open chat and appears on the others when they are hovered.
export function ChatRow({ chat, current }: ChatRowProps) {
  const reveal = current ? "opacity-100" : "opacity-0 group-hover:opacity-100 group-focus-within:opacity-100"

  return (
    <div
      className={`group relative flex items-center rounded-control transition-colors duration-100 ${
        current ? "bg-hover-2" : "hover:bg-hover"
      }`}
    >
      <Link
        href={agentChatPath(chat.id)}
        className={`min-w-0 flex-1 truncate py-1.5 pr-8 pl-2.5 text-[13px] ${current ? "text-ink" : "text-ink-2"}`}
      >
        {chat.title}
      </Link>
      <ChatRowActions chat={chat} className={`absolute right-1 ${reveal} data-[state=open]:opacity-100`} />
    </div>
  )
}
