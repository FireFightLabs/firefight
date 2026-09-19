import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { useEffect, useRef, useState } from "react"

import { AGENT_CHANNEL, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import type { AgentStep, AgentStream, StepStatus, StreamEventType } from "@/pages/agent/types"
import type { AgentChatMessage } from "@/types/serializers"

// A socket that drops mid turn would leave the answer unseen, so the page asks for it once instead.
const RECOVERY_MS = 4000
const RELOADED_PROPS = [ "messages", "conversations" ]

interface StreamEvent {
  type: StreamEventType
  text?: string
  key?: string
  title?: string
  headline?: string
  asked?: [ string, string ][]
  status?: StepStatus
}

export function useAgentStream(
  conversationId: string | undefined,
  messages: AgentChatMessage[] | undefined,
): AgentStream {
  const [ busy, setBusy ] = useState(false)
  const [ text, setText ] = useState("")
  const [ steps, setSteps ] = useState<AgentStep[]>([])
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
  const last = messages?.[messages.length - 1]

  // A turn already running when the page opened has no thinking event to announce it.
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
            router.reload({ only: RELOADED_PROPS })
          }
        },
        disconnected() {
          if (!working.current) {
            return
          }

          recovery.current = window.setTimeout(() => router.reload({ only: RELOADED_PROPS }), RECOVERY_MS)
        },
      },
    )

    return () => {
      stopRecovery()
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ conversationId ])

  // Once the reply is saved it renders from the chat, so the streamed copy goes in the same render,
  // not a frame later.
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
