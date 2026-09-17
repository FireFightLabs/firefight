import { Link, router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { agentChatPath, agentChatsPath } from "@/lib/routes"
import type { AgentChat } from "@/types/serializers"

interface ChatListProps {
  chats: AgentChat[]
  currentId?: string
  className: string
}

export function ChatList({ chats, currentId, className }: ChatListProps) {
  function startChat() {
    router.post(agentChatsPath())
  }

  return (
    <aside className={`shrink-0 flex-col gap-2 ${className}`}>
      <button
        type="button"
        onClick={startChat}
        className="flex items-center gap-2 rounded-control bg-surface px-3 py-2 text-[13px] text-ink shadow-btn transition-colors duration-100 hover:bg-hover"
      >
        <IconPlus className="size-4 text-ink-2" />
        New chat
      </button>
      <nav className="flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto">
        {chats.map((chat) => (
          <Link
            key={chat.id}
            href={agentChatPath(chat.id)}
            className={`truncate rounded-control px-3 py-2 text-[13px] transition-colors duration-100 ${
              chat.id === currentId ? "bg-hover-2 text-ink" : "text-ink-2 hover:bg-hover"
            }`}
          >
            {chat.title}
          </Link>
        ))}
      </nav>
    </aside>
  )
}
