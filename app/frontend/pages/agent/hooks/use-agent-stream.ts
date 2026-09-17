import { createConsumer } from "@rails/actioncable"
import { router } from "@inertiajs/react"
import { useEffect, useRef, useState } from "react"

import { AGENT_CHANNEL, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS, CHAT_MESSAGE_ROLES } from "@/lib/generated/constants"
import type { AgentStep } from "@/pages/agent/components/agent-steps"
import type { AgentChatMessage } from "@/types/serializers"

// A socket that drops mid turn would leave the answer unseen, so the page asks for it once instead.
const RECOVERY_MS = 4000

export type TurnState = "idle" | "working"

type StepStatus = (typeof AGENT_STEP_STATUSES)[keyof typeof AGENT_STEP_STATUSES]

export interface AgentStream {
  state: TurnState
  text: string
  steps: AgentStep[]
}

interface StreamEvent {
  type: string
  text?: string
  key?: string
  title?: string
  asked?: [ string, string ][]
  status?: StepStatus
}

export function useAgentStream(
  conversationId: string | undefined,
  messages: AgentChatMessage[] | undefined,
): AgentStream {
  const [ state, setState ] = useState<TurnState>("idle")
  const [ text, setText ] = useState("")
  const [ steps, setSteps ] = useState<AgentStep[]>([])
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
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
      { channel: AGENT_CHANNEL, id: conversationId },
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
          if (event.type === AGENT_STREAM_EVENTS.ANSWERED || event.type === AGENT_STREAM_EVENTS.FAILED) {
            setState("idle")
            router.reload({ only: [ "messages", "conversations" ] })
          }
        },
        disconnected() {
          if (!working.current) {
            return
          }

          recovery.current = window.setTimeout(
            () => router.reload({ only: [ "messages", "conversations" ] }),
            RECOVERY_MS,
          )
        },
      },
    )

    return () => {
      window.clearTimeout(recovery.current)
      subscription.unsubscribe()
      consumer.disconnect()
    }
  }, [ conversationId ])

  // Once the reply is saved it renders from the chat, so the streamed copy goes in the same render,
  // not a frame later.
  const saved = last?.role !== CHAT_MESSAGE_ROLES.USER

  return { state, text: saved ? "" : text, steps: saved ? [] : steps }
}

function withStep(shown: AgentStep[], event: StreamEvent): AgentStep[] {
  const step = {
    key: event.key ?? "",
    title: event.title ?? "",
    asked: event.asked ?? [],
    status: event.status ?? AGENT_STEP_STATUSES.RUNNING,
  }
  const already = shown.findIndex((candidate) => candidate.key === step.key)
  if (already < 0) {
    return [ ...shown, step ]
  }

  return shown.map((candidate) => (candidate.key === step.key ? { ...candidate, ...step } : candidate))
}
