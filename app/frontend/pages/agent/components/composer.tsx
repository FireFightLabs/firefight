import { useState } from "react"

import PromptBar, { type PromptAttachment } from "@/components/agent-ui/prompt-bar"
import { agentChatsIncidentsPath } from "@/lib/routes"
import { UPLOAD_STATES, type ComposerAttachment, useAttachmentUploads } from "@/pages/agent/hooks/use-attachment-uploads"
import { useRemoteSearch } from "@/hooks/use-remote-search"
import { ask, stopChat } from "@/pages/agent/lib/chat-updates"
import type { AgentChatAttachmentRules, AgentChatIncident } from "@/types/serializers"

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
  // Turns send into Stop while nothing is typed. A message sent while the agent works joins its answer at the next step.
  busy: boolean
  fill: ComposerFill | null
  attachmentRules: AgentChatAttachmentRules
}

function promptAttachment(item: ComposerAttachment): PromptAttachment {
  return {
    key: item.key, name: item.name, size: item.size, previewUrl: item.previewUrl, progress: item.progress,
    uploading: item.state === UPLOAD_STATES.UPLOADING, error: item.error, note: item.note,
  }
}

export function Composer({ conversationId, incidents, busy, fill, attachmentRules }: ComposerProps) {
  const { results, search } = useRemoteSearch<AgentChatIncident>(incidentSearchPath)
  const uploads = useAttachmentUploads(attachmentRules)
  // Set when Stop is pressed and cleared by the next question, so the hint says so until the answer ends.
  const [ stopRequested, setStopRequested ] = useState(false)
  const stopping = busy && stopRequested

  function send(question: string) {
    if (question.trim().length === 0 && uploads.uploaded.length === 0) {
      return
    }

    setStopRequested(false)
    ask(conversationId, question, uploads.uploaded, uploads.previewsById)
    uploads.clear()
  }

  function stop() {
    if (conversationId) {
      setStopRequested(true)
      stopChat(conversationId)
    }
  }

  function placeholder() {
    if (stopping) {
      return "Stopping"
    }
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
        onStop={busy && !stopping && conversationId ? stop : undefined}
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
        attachments={{
          items: uploads.items.map(promptAttachment), accept: attachmentRules.accept, notice: uploads.notice,
          sendable: uploads.sendable, onAdd: uploads.add, onRemove: uploads.remove,
        }}
      />
    </div>
  )
}
