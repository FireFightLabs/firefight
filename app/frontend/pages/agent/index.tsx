import { Head, Link, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ChatList } from "@/pages/agent/components/chat-list"
import { Composer } from "@/pages/agent/components/composer"
import { Thread } from "@/pages/agent/components/thread"
import { useLiveMessages } from "@/pages/agent/hooks/use-live-messages"
import { agentChatsPath } from "@/lib/routes"
import type { AgentChat, AgentChatMessage } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AgentPageProps extends SharedProps {
  conversations: AgentChat[]
  conversation?: AgentChat
  messages?: AgentChatMessage[]
}

export default function AgentPage() {
  const { conversations, conversation, messages } = usePage<AgentPageProps>().props
  const state = useLiveMessages(conversation?.id, messages)

  const listClass = conversation ? "hidden w-64 md:flex" : "flex w-full md:w-64"
  const threadClass = conversation ? "flex" : "hidden md:flex"

  return (
    <AuthenticatedLayout title="Agent">
      <Head title="Agent" />
      <div className="flex h-[calc(100dvh-var(--header-height)-2.5rem)] gap-4 px-4 pb-4 lg:px-6">
        <ChatList chats={conversations} currentId={conversation?.id} className={listClass} />
        <div className={`min-h-0 min-w-0 flex-1 flex-col gap-3 ${threadClass}`}>
          {conversation && (
            <Link href={agentChatsPath()} className="text-[13px] text-ink-2 md:hidden">
              All chats
            </Link>
          )}
          <Thread messages={messages ?? []} state={state} empty={!conversation} />
          <Composer conversationId={conversation?.id} busy={state === "working"} />
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
