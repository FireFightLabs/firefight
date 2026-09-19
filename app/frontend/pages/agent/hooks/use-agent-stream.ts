import { createConsumer } from "@rails/actioncable"
import { useEffect, useRef, useState } from "react"

import { AGENT_CHANNEL, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import { refreshOpenChat } from "@/pages/agent/lib/chat-updates"
import type { AgentStep, AgentStream, StepStatus, StreamEventType } from "@/pages/agent/types"
import type { AgentChatMessage } from "@/types/serializers"

// If the socket drops mid turn, the answer is fetched once instead of waited for.
const RECOVERY_MS = 4000

interface StreamEvent {
  type: StreamEventType
  text?: string
  key?: string
  title?: string
  headline?: string
  asked?: [ string, string ][]
  status?: StepStatus
}

export function useAgentStream(conversationId: string | null, messages: AgentChatMessage[]): AgentStream {
  const [ busy, setBusy ] = useState(false)
  const [ text, setText ] = useState("")
  const [ steps, setSteps ] = useState<AgentStep[]>([])
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
  const last = messages[messages.length - 1]

  // A turn already running when the page opened sends no thinking event.
  useEffect(() => {
    setBusy(last?.role === CHAT_MESSAGE_ROLES.USER)
    setText("")
    setSteps([])
  }, [ conversationId, last?.id, last?.role ])

  useEffect(() => {
    working.current = busy
  }, [ busy ])

  useEffect(() => {
    if (!conversationId) {
      return
    }

    function stopRecovery() {
      window.clearTimeout(recovery.current)
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: AGENT_CHANNEL, id: conversationId },
      {
        connected: stopRecovery,
        received(event: StreamEvent) {
          stopRecovery()
          if (event.type === AGENT_STREAM_EVENTS.THINKING) {
            setBusy(true)
            setText("")
            setSteps([])
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.CHUNK) {
            setText((written) => written + (event.text ?? ""))
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.STEP) {
            setSteps((shown) => withStep(shown, event))
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.ANSWERED || event.type === AGENT_STREAM_EVENTS.FAILED) {
            setBusy(false)
            refreshOpenChat()
          }
        },
        disconnected() {
          if (!working.current) {
            return
          }

          recovery.current = window.setTimeout(refreshOpenChat, RECOVERY_MS)
        },
      },
    )

    return () => {
      stopRecovery()
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ conversationId ])

  // The streamed copy hides in the same render the saved reply appears, so the answer never shows twice.
  const saved = last?.role !== CHAT_MESSAGE_ROLES.USER

  return { busy, text: saved ? "" : text, steps: saved ? [] : steps }
}

function withStep(shown: AgentStep[], event: StreamEvent): AgentStep[] {
  const step = {
    key: event.key ?? "",
    title: event.title ?? "",
    headline: event.headline ?? "",
    asked: event.asked ?? [],
    status: event.status ?? AGENT_STEP_STATUSES.RUNNING,
  }
  const already = shown.findIndex((candidate) => candidate.key === step.key)
  if (already < 0) {
    return [ ...shown, step ]
  }

  return shown.map((candidate) => (candidate.key === step.key ? { ...candidate, ...step } : candidate))
}
