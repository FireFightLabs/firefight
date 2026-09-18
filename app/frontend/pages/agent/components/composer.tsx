import { router } from "@inertiajs/react"

import PromptBar from "@/components/agent-ui/prompt-bar"
import { agentChatAskPath, agentChatsPath } from "@/lib/routes"
import type { AgentChatIncident } from "@/types/serializers"

interface ComposerProps {
  conversationId?: string
  incidents: AgentChatIncident[]
  busy: boolean
}

export function Composer({ conversationId, incidents, busy }: ComposerProps) {
  // With no chat open, the first question is what starts one.
  function send(question: string) {
    if (question.trim().length === 0) {
      return
    }

    const path = conversationId ? agentChatAskPath(conversationId) : agentChatsPath()
    router.post(path, { question }, { preserveScroll: true })
  }

  function placeholder() {
    if (busy) {
      return "The agent is working"
    }

    return "Ask the agent, or @ an incident"
  }

  // @ offers the incidents the agent can already read. The model picker and dictation are theirs
  // and stay off until a model choice and a transcript mean something here.
  const sources = incidents.map((incident) => ({
    key: incident.id,
    name: incident.identifier,
    desc: incident.name,
    glyph: "layers",
  }))

  return (
    <div className="mx-auto w-full max-w-3xl">
      <PromptBar
        demo={false}
        busy={busy}
        modelPicker={false}
        dictation={false}
        sources={sources}
        commands={[]}
        placeholder={placeholder()}
        onSend={send}
      />
    </div>
  )
}
