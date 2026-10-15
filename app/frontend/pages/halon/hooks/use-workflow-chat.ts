import { router } from "@inertiajs/react"
import { useMemo, useState } from "react"

import { type ChatStreamHandlers, useChatStream } from "@/hooks/use-chat-stream"
import type { StreamEvent } from "@/lib/agent-chat/stream-order"
import type { AgentStream } from "@/lib/agent-chat/types"
import { AGENT_CARD_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS, WORKFLOW_CANVAS_PROPS } from "@/lib/generated/constants"
import { workflowChatPath, workflowChatStopPath } from "@/lib/routes"
import { CANVAS_VISIT, CHAT_VISIT } from "@/pages/halon/hooks/use-workflow-edits"
import type { AgentChat } from "@/types/serializers"

export interface WorkflowChat {
  stream: AgentStream
  // The question sent and not yet saved, shown at once so the person sees it went.
  pending: string | null
  // A new chat was asked for, so the next question starts one and the old one stays in the person's chats.
  fresh: boolean
  ask: (question: string) => void
  stop: () => void
  startFresh: () => void
}

function reloadChat() {
  router.reload(CHAT_VISIT)
}

// What the chat's live connection reloads lands on the page as it is, so it shows no progress bar either.
const CANVAS_RELOAD = { ...CANVAS_VISIT, showProgress: false }

// A step that finished may have proposed a change, which the canvas shows as it lands. One that drew a chart reloads the
// charts, so the answer has it when it places it.
function onStreamed(event: StreamEvent) {
  if (event.type === AGENT_STREAM_EVENTS.STEP && event.status !== AGENT_STEP_STATUSES.RUNNING) {
    router.reload(CANVAS_RELOAD)
  }
  if (event.type === AGENT_STREAM_EVENTS.STEP && event.card?.kind === AGENT_CARD_KINDS.CHART) {
    router.reload({ ...CHAT_VISIT, only: [ WORKFLOW_CANVAS_PROPS.CHARTS ] })
  }
}

function onNotice(event: StreamEvent): boolean {
  if (event.type === AGENT_STREAM_EVENTS.HELPERS) {
    router.reload({ ...CHAT_VISIT, only: [ WORKFLOW_CANVAS_PROPS.HELPERS, WORKFLOW_CANVAS_PROPS.CHARTS ] })
    return true
  }
  if (event.type === AGENT_STREAM_EVENTS.HELD_CALL) {
    router.reload({ ...CHAT_VISIT, only: [ WORKFLOW_CANVAS_PROPS.CHAT_WAITING ] })
    return true
  }
  return false
}

// A turn's end reloads the canvas too, since what Halon proposed shows there.
function reloadAll() {
  reloadChat()
  router.reload(CANVAS_RELOAD)
}

const HANDLERS: ChatStreamHandlers = { reloadChat: reloadAll, onNotice, onStreamed }

// The chat with Halon beside a workflow's canvas: asking, stopping, starting a new one, and its live turn.
export function useWorkflowChat(workflowId: string, chat: AgentChat | null): WorkflowChat {
  const [ fresh, setFresh ] = useState(false)
  const [ pending, setPending ] = useState<string | null>(null)
  const shown = fresh ? null : chat
  const stream = useChatStream(shown?.id ?? null, shown?.busy ?? false, HANDLERS)

  return useMemo(() => {
    function settled() {
      setPending(null)
    }

    function asked() {
      setFresh(false)
    }

    function ask(question: string) {
      const trimmed = question.trim()
      if (!trimmed) {
        return
      }
      setPending(trimmed)
      router.post(workflowChatPath(workflowId), { question: trimmed, fresh }, { ...CHAT_VISIT, onSuccess: asked, onFinish: settled })
    }

    function stop() {
      router.post(workflowChatStopPath(workflowId), {}, CHAT_VISIT)
    }

    function startFresh() {
      setFresh(true)
    }

    return { stream, pending, fresh, ask, stop, startFresh }
  }, [ workflowId, stream, pending, fresh ])
}
