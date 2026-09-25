import { useState } from "react"
import { Head, Link, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { ChatList } from "@/pages/agent/components/chat-list"
import { StartExamples, StartHeading } from "@/pages/agent/components/chat-start"
import { Composer, type ComposerFill } from "@/pages/agent/components/composer"
import { Thread } from "@/pages/agent/components/thread"
import { useAgentStream } from "@/pages/agent/hooks/use-agent-stream"
import { OPEN_CHAT_VISIT, closeRun, startNewChat } from "@/pages/agent/lib/chat-updates"
import { InvestigationSheet } from "@/components/investigations/investigation-sheet"
import { AGENT_CHAT_PROPS } from "@/lib/generated/constants"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import type { AgentPageProps } from "@/pages/agent/types"
import { agentChatsPath } from "@/lib/routes"

const BACK_LINK_CLASS = "px-4 pt-3 text-left text-[13px] text-ink-2 md:hidden"

export default function AgentPage() {
  const { conversations, archivedCount, conversation, incidents, messages, confirmations, openInvestigation, waitingMessages } = usePage<AgentPageProps>().props
  const conversationId = conversation?.id ?? null
  const stream = useAgentStream(conversationId, conversation?.busy ?? false)
  const [ fill, setFill ] = useState<ComposerFill | null>(null)
  // Below 48rem the page is one panel at a time, and New chat has to show the start page rather than the list.
  const [ composing, setComposing ] = useState(false)
  const [ declaring, setDeclaring ] = useState(false)

  function fillComposer(draft: string) {
    setFill((current) => ({ draft, key: (current?.key ?? 0) + 1 }))
  }

  // Already on a new chat, so a visit would only flicker.
  function beginNewChat() {
    setComposing(true)
    if (conversationId) {
      startNewChat()
    }
  }

  function backToList() {
    setComposing(false)
  }

  function closeInvestigation() {
    if (conversationId) {
      closeRun(conversationId)
    }
  }

  function startDeclaring() {
    setDeclaring(true)
  }

  const starting = !conversation && composing
  const listClass = conversation || starting ? "hidden md:flex" : "flex"
  // A new chat holds the composer in the middle, an open chat at the foot, and the move between the two is animated.
  const threadClass = conversation ? "agent-thread-open grid" : starting ? "grid" : "hidden md:grid"

  return (
    <AuthenticatedLayout title="Chat" sidebarCollapsed>
      <Head title="Chat" />
      <div className="agent-ui agent-chat">
        <ChatList
          chats={conversations}
          archivedCount={archivedCount}
          currentId={conversationId}
          className={listClass}
          onNewChat={beginNewChat}
        />
        <section className={`agent-thread min-w-0 ${threadClass}`}>
          <div className="flex min-h-0 flex-col">
            {conversation ? (
              <>
                <Link href={agentChatsPath()} {...OPEN_CHAT_VISIT} onClick={backToList} className={BACK_LINK_CLASS}>
                  All chats
                </Link>
                <Thread
                  conversationId={conversationId}
                  confirmations={confirmations}
                  messages={messages}
                  waiting={waitingMessages}
                  stream={stream}
                />
              </>
            ) : (
              <>
                <button type="button" onClick={backToList} className={BACK_LINK_CLASS}>
                  All chats
                </button>
                <StartHeading />
              </>
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
      <InvestigationSheet
        investigation={openInvestigation}
        prop={AGENT_CHAT_PROPS.OPEN_INVESTIGATION}
        onClose={closeInvestigation}
        onDeclare={startDeclaring}
      />
      <LifecycleFormDialog
        incidentId={null}
        form="declare"
        open={declaring}
        onOpenChange={setDeclaring}
        fromInvestigationId={openInvestigation?.id ?? null}
        suggestedName={openInvestigation?.question}
      />
    </AuthenticatedLayout>
  )
}
