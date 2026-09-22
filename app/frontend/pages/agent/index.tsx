import { useState } from "react"
import { Head, Link, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ChatList } from "@/pages/agent/components/chat-list"
import { StartExamples, StartHeading } from "@/pages/agent/components/chat-start"
import { Composer, type ComposerFill } from "@/pages/agent/components/composer"
import { Thread } from "@/pages/agent/components/thread"
import { useAgentStream } from "@/pages/agent/hooks/use-agent-stream"
import { OPEN_CHAT_VISIT } from "@/pages/agent/lib/chat-updates"
import type { AgentPageProps } from "@/pages/agent/types"
import { agentChatsPath } from "@/lib/routes"

export default function AgentPage() {
  const { conversations, archivedCount, conversation, incidents, messages, confirmations } = usePage<AgentPageProps>().props
  const conversationId = conversation?.id ?? null
  const stream = useAgentStream(conversationId, messages)
  const [ fill, setFill ] = useState<ComposerFill | null>(null)

  function fillComposer(draft: string) {
    setFill((current) => ({ draft, key: (current?.key ?? 0) + 1 }))
  }

  const listClass = conversation ? "hidden md:flex" : "flex"
  // A new chat holds the composer in the middle, an open chat at the foot, and the move between the two is animated.
  const threadClass = conversation ? "agent-thread-open grid" : "hidden md:grid"

  return (
    <AuthenticatedLayout title="Chat" sidebarCollapsed>
      <Head title="Chat" />
      <div className="agent-ui agent-chat">
        <ChatList chats={conversations} archivedCount={archivedCount} currentId={conversationId} className={listClass} />
        <section className={`agent-thread min-w-0 ${threadClass}`}>
          <div className="flex min-h-0 flex-col">
            {conversation ? (
              <>
                <Link href={agentChatsPath()} {...OPEN_CHAT_VISIT} className="px-4 pt-3 text-[13px] text-ink-2 md:hidden">
                  All chats
                </Link>
                <Thread
                  conversationId={conversationId}
                  confirmations={confirmations}
                  messages={messages}
                  stream={stream}
                />
              </>
            ) : (
              <StartHeading />
            )}
          </div>
          <div className="p-3">
            <Composer
              conversationId={conversationId}
              incidents={incidents}
              busy={stream.busy}
              fill={fill}
            />
          </div>
          <div className="min-h-0 overflow-hidden">
            {!conversation && <StartExamples onPick={fillComposer} />}
          </div>
        </section>
      </div>
    </AuthenticatedLayout>
  )
}
