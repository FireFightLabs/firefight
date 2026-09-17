import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { useEffect, useRef, useState } from "react"

import { AGENT_STREAM_EVENTS, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import type { AgentChatMessage } from "@/types/serializers"

const CHANNEL = "ConversationChannel"
// A socket that drops mid turn would leave the answer unseen, so the page asks for it once instead.
const RECOVERY_MS = 4000

export type TurnState = "idle" | "working" | "failed"

export interface LiveStep {
  key: string
  title: string
  status: string
}

export interface AgentStream {
  state: TurnState
  text: string
  steps: LiveStep[]
}

interface StreamEvent {
  type: string
  text?: string
  key?: string
  title?: string
  status?: string
}

export function useAgentStream(
  conversationId: string | undefined,
  messages: AgentChatMessage[] | undefined,
): AgentStream {
  const [ state, setState ] = useState<TurnState>("idle")
  const [ text, setText ] = useState("")
  const [ steps, setSteps ] = useState<LiveStep[]>([])
  const working = useRef(false)
  const last = messages?.[messages.length - 1]

  // A turn already running when the page opened has no thinking event to announce it.
  useEffect(() => {
    setState(last?.role === CHAT_MESSAGE_ROLES.USER ? "working" : "idle")
    setText("")
    setSteps([])
  }, [ conversationId, last?.id, last?.role ])

  useEffect(() => {
    working.current = state === "working"
  }, [ state ])

  useEffect(() => {
    if (!conversationId) {
      return
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: CHANNEL, id: conversationId },
      {
        received(event: StreamEvent) {
          if (event.type === AGENT_STREAM_EVENTS.THINKING) {
            setState("working")
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
          if (event.type === AGENT_STREAM_EVENTS.ANSWERED) {
            setState("idle")
            router.reload({ only: [ "messages", "conversations" ] })
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.FAILED) {
            setState("failed")
          }
        },
        disconnected() {
          if (!working.current) {
            return
          }

          window.setTimeout(() => router.reload({ only: [ "messages", "conversations" ] }), RECOVERY_MS)
        },
      },
    )

    return () => {
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ conversationId ])

  // Once the reply is saved it renders from the chat, so the streamed copy of it steps aside in the
  // same render rather than a frame later.
  const saved = last?.role !== CHAT_MESSAGE_ROLES.USER

  return { state, text: saved ? "" : text, steps: saved ? [] : steps }
}

function withStep(shown: LiveStep[], event: StreamEvent): LiveStep[] {
  const step = { key: event.key ?? "", title: event.title ?? "", status: event.status ?? "" }
  const already = shown.findIndex((candidate) => candidate.key === step.key)
  if (already < 0) {
    return [ ...shown, step ]
  }

  return shown.map((candidate) => (candidate.key === step.key ? { ...candidate, ...step } : candidate))
}
