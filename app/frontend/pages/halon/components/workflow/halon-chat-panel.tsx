import { router } from "@inertiajs/react"
import { IconExternalLink, IconPlus, IconSparkles, IconX } from "@tabler/icons-react"
import { useState } from "react"

import PromptBar from "@/components/agent-ui/prompt-bar"
import { Button } from "@/components/ui/button"
import { agentChatPath } from "@/lib/routes"
import { ChatTranscript } from "@/pages/halon/components/workflow/chat-transcript"
import { StarterButton } from "@/pages/halon/components/workflow/starter-button"
import { useWorkflowChat } from "@/pages/halon/hooks/use-workflow-chat"
import type { AgentChat, AgentChatMessage } from "@/types/serializers"

// Questions that show what Halon can do here, each handed to the composer to finish rather than sent.
const STARTERS = [
  "What does this workflow do, step by step?",
  "Add a step that waits for the deploy to finish before checking.",
  "Why did the last run fail, and what would fix it?",
]

interface HalonChatPanelProps {
  workflowId: string
  chat: AgentChat | null
  messages: AgentChatMessage[]
  // Something in the chat waits on the person, which only the full chat lets them answer.
  waiting: boolean
  // Why the person cannot ask Halon here, such as Halon being off for the workspace, or null when they can.
  unavailable: string | null
  onClose: () => void
}

interface Fill {
  draft: string
  key: number
}

// Halon beside the canvas. The person asks it to explain, add or change steps, and its changes land on the canvas as
// suggestions they accept or dismiss. The chat is also one of their chats with Halon, where it opens in full.
export function HalonChatPanel({ workflowId, chat, messages, waiting, unavailable, onClose }: HalonChatPanelProps) {
  const conversation = useWorkflowChat(workflowId, chat)
  const [ fill, setFill ] = useState<Fill | null>(null)
  const shown = conversation.fresh ? null : chat
  const fullChatUrl = shown ? agentChatPath(shown.id) : null
  const shownMessages = shown ? messages : []
  const empty = shownMessages.length === 0 && !conversation.pending
  // Stop was pressed on the answer under way, as the server keeps it until the answer ends.
  const stopping = conversation.stream.busy && (shown?.stopRequested ?? false)

  function pickStarter(starter: string) {
    setFill((current) => ({ draft: starter, key: (current?.key ?? 0) + 1 }))
  }

  function openImage() {
    if (fullChatUrl) {
      router.visit(fullChatUrl)
    }
  }

  function placeholder() {
    if (stopping) {
      return "Stopping"
    }
    if (conversation.stream.busy) {
      return "Add something while Halon works"
    }
    return "Ask Halon about this workflow"
  }

  return (
    <div className="agent-ui flex h-full min-h-0 flex-col bg-background">
      <div className="flex items-center gap-2 border-b border-border px-4 py-2.5">
        <IconSparkles className="size-4 text-halon" />
        <h2 className="text-[13px] font-medium text-fg-headline">Halon</h2>
        <div className="grow" />
        {shown && (
          <Button type="button" variant="ghost" size="sm" onClick={conversation.startFresh}>
            <IconPlus className="size-4" />
            New chat
          </Button>
        )}
        {fullChatUrl && (
          <Button asChild variant="ghost" size="icon" className="size-8">
            <a href={fullChatUrl} aria-label="Open the full chat">
              <IconExternalLink className="size-4" />
            </a>
          </Button>
        )}
        <Button type="button" variant="ghost" size="icon" className="size-8" aria-label="Close Halon" onClick={onClose}>
          <IconX className="size-4" />
        </Button>
      </div>
      <div className="min-h-0 flex-1 overflow-y-auto">
        {empty ? (
          <div className="flex flex-col gap-3 px-4 py-6">
            <p className="text-[13px] leading-relaxed text-fg-secondary">
              Ask Halon to explain this workflow, add or change its steps, or look into a run. What it changes shows on the
              canvas as a suggestion you accept or dismiss.
            </p>
            {!unavailable && STARTERS.map((starter) => <StarterButton key={starter} starter={starter} onPick={pickStarter} />)}
          </div>
        ) : (
          <ChatTranscript messages={shownMessages} stream={conversation.stream} pending={conversation.pending} fullChatUrl={fullChatUrl} onOpenImage={openImage} />
        )}
      </div>
      {waiting && fullChatUrl && !conversation.fresh && (
        <a href={fullChatUrl} className="mx-4 mb-2 rounded-md border border-halon-border px-3 py-2 text-[12.5px] text-halon hover:bg-surface-hover">
          Halon is waiting on you to confirm something. Open the full chat to answer it.
        </a>
      )}
      <div className="px-3 pb-3">
        {unavailable ? (
          <p className="rounded-md border border-border px-3 py-2 text-[12.5px] text-fg-muted">{unavailable}</p>
        ) : (
          <PromptBar
            key={fill?.key ?? 0}
            sources={[]}
            commands={[]}
            dictation={false}
            placeholder={placeholder()}
            initialDraft={fill?.draft}
            autoFocus={fill !== null}
            onSend={conversation.ask}
            onStop={conversation.stream.busy && !stopping ? conversation.stop : undefined}
          />
        )}
      </div>
    </div>
  )
}
