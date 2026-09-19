import PromptBar from "@/components/agent-ui/prompt-bar"
import { agentChatsIncidentsPath } from "@/lib/routes"
import { useRemoteSearch } from "@/pages/agent/hooks/use-remote-search"
import { ask } from "@/pages/agent/lib/chat-updates"
import type { AgentChatIncident } from "@/types/serializers"

function incidentSearchPath(query: string) {
  return agentChatsIncidentsPath({ q: query })
}

interface ComposerProps {
  conversationId: string | null
  incidents: AgentChatIncident[]
  busy: boolean
}

export function Composer({ conversationId, incidents, busy }: ComposerProps) {
  const { results, search } = useRemoteSearch<AgentChatIncident>(incidentSearchPath)

  function send(question: string) {
    if (question.trim().length === 0) {
      return
    }

    ask(conversationId, question)
  }

  function placeholder() {
    if (busy) {
      return "The agent is working"
    }

    return "Ask the agent, or @ an incident"
  }

  // @ offers the newest active incidents, and searches every active one once the person types. The
  // model picker and dictation are theirs and stay off until a model choice and a transcript mean
  // something here.
  const sources = (results ?? incidents).map((incident) => ({
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
        onSourceSearch={search}
        sourceHint="Type to search incidents"
      />
    </div>
  )
}
