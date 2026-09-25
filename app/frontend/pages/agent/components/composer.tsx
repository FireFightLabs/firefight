import PromptBar from "@/components/agent-ui/prompt-bar"
import { agentChatsIncidentsPath } from "@/lib/routes"
import { useRemoteSearch } from "@/pages/agent/hooks/use-remote-search"
import { ask } from "@/pages/agent/lib/chat-updates"
import type { AgentChatIncident } from "@/types/serializers"

function incidentSearchPath(query: string) {
  return agentChatsIncidentsPath({ q: query })
}

// A question handed to the composer to finish. The key changes on every hand over, so the same example can be picked twice.
export interface ComposerFill {
  draft: string
  key: number
}

interface ComposerProps {
  conversationId: string | null
  incidents: AgentChatIncident[]
  // Only changes the hint. A message sent while the agent works joins its answer at the next step.
  busy: boolean
  fill: ComposerFill | null
}

export function Composer({ conversationId, incidents, busy, fill }: ComposerProps) {
  const { results, search } = useRemoteSearch<AgentChatIncident>(incidentSearchPath)

  function send(question: string) {
    if (question.trim().length === 0) {
      return
    }

    ask(conversationId, question)
  }

  function placeholder() {
    if (busy) {
      return "Add something while Halon works"
    }

    return "Ask the agent, or @ an incident"
  }

  // The model picker and dictation stay off until there is something behind them.
  const sources = (results ?? incidents).map((incident) => ({
    key: incident.id,
    name: incident.identifier,
    desc: incident.name,
    glyph: "layers",
  }))

  // A new chat and a handed over question take the caret. An opened chat does not, so the keyboard stays down on a phone.
  const takesFocus = fill !== null || conversationId === null

  return (
    <div className="mx-auto w-full max-w-3xl">
      <PromptBar
        key={fill?.key ?? 0}
        modelPicker={false}
        dictation={false}
        sources={sources}
        commands={[]}
        placeholder={placeholder()}
        initialDraft={fill?.draft}
        autoFocus={takesFocus}
        onSend={send}
        onSourceSearch={search}
        sourceHint="Type to search incidents"
      />
    </div>
  )
}
