import { ChatRow } from "@/pages/agent/components/chat-row"
import type { AgentChat } from "@/types/serializers"

interface ChatListSectionProps {
  label?: string
  chats: AgentChat[]
  currentId?: string
}

export function ChatListSection({ label, chats, currentId }: ChatListSectionProps) {
  if (chats.length === 0) {
    return null
  }

  return (
    <div className="flex flex-col gap-0.5">
      {label && <p className="px-2.5 pb-1 text-[12px] text-ink-3">{label}</p>}
      {chats.map((chat) => (
        <ChatRow key={chat.id} chat={chat} current={chat.id === currentId} />
      ))}
    </div>
  )
}
