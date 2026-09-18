import { Head, Link, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ChatList } from "@/pages/agent/components/chat-list"
import { Composer } from "@/pages/agent/components/composer"
import { Thread } from "@/pages/agent/components/thread"
import { ThreadHeader } from "@/pages/agent/components/thread-header"
import { useAgentStream } from "@/pages/agent/hooks/use-agent-stream"
import { agentChatsPath } from "@/lib/routes"
import type { AgentChat, AgentChatIncident, AgentChatMessage } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AgentPageProps extends SharedProps {
  conversations: AgentChat[]
  conversation?: AgentChat
  incidents: AgentChatIncident[]
  messages?: AgentChatMessage[]
}

export default function AgentPage() {
  const { conversations, conversation, incidents, messages } = usePage<AgentPageProps>().props
  const stream = useAgentStream(conversation?.id, messages)

  // One column at a time on a phone: the list, or the chat opened from it.
  const listClass = conversation ? "hidden md:flex" : "flex"
  const threadClass = conversation ? "flex" : "hidden md:flex"

  return (
    <AuthenticatedLayout title="Agent" sidebarCollapsed>
      <Head title="Agent" />
      <div className="agent-ui agent-chat">
        <ChatList chats={conversations} currentId={conversation?.id} className={listClass} />
        <section className={`min-h-0 min-w-0 flex-1 flex-col ${threadClass}`}>
          {conversation && (
            <>
              <Link href={agentChatsPath()} className="px-4 pt-3 text-[13px] text-ink-2 md:hidden">
                All chats
              </Link>
              <ThreadHeader chat={conversation} startedIso={messages?.[0]?.at} />
            </>
          )}
          <Thread messages={messages ?? []} stream={stream} empty={!conversation} />
          <div className="border-t border-line p-3">
            <Composer
              conversationId={conversation?.id}
              incidents={incidents}
              busy={stream.state === "working"}
            />
          </div>
        </section>
      </div>
    </AuthenticatedLayout>
  )
}
