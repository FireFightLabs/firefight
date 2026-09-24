import { createConsumer } from "@rails/actioncable"
import { useEffect, useRef, useState } from "react"

import { AGENT_CHANNEL, AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import { refreshOpenChat, refreshRuns } from "@/pages/agent/lib/chat-updates"
import type { AgentCard, AgentStep, AgentStream, StepKind, StepStatus, StreamEventType } from "@/pages/agent/types"

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
  kind?: StepKind
  seconds?: number
  card?: AgentCard | null
}

// The server says whether an answer is owed. The page never guesses it from the last message, which the empty reply
// saved before the model answers would flip within milliseconds of the question.
export function useAgentStream(conversationId: string | null, owed: boolean): AgentStream {
  const [ ended, setEnded ] = useState(false)
  const [ text, setText ] = useState("")
  const [ steps, setSteps ] = useState<AgentStep[]>([])
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
  const busy = owed && !ended

  useEffect(() => {
    setEnded(false)
    setText("")
    setSteps([])
  }, [ conversationId, owed ])

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
            setEnded(false)
            setText("")
            setSteps([])
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.CHUNK) {
            setText((written) => written + (event.text ?? ""))
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.INVESTIGATION) {
            refreshRuns()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.STEP) {
            setSteps((shown) => withStep(shown, event))
            return
          }
          if (
            event.type === AGENT_STREAM_EVENTS.ANSWERED ||
            event.type === AGENT_STREAM_EVENTS.FAILED ||
            event.type === AGENT_STREAM_EVENTS.WAITING
          ) {
            setEnded(true)
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

  // The streamed copy is shown only while the server owes an answer, so it hides in the same render the saved reply appears.
  return { busy, owed, text: owed ? text : "", steps: owed ? steps : [] }
}

function withStep(shown: AgentStep[], event: StreamEvent): AgentStep[] {
  const step = {
    key: event.key ?? "",
    title: event.title ?? "",
    headline: event.headline ?? "",
    asked: event.asked ?? [],
    status: event.status ?? AGENT_STEP_STATUSES.RUNNING,
    kind: event.kind ?? AGENT_STEP_KINDS.ACT,
    seconds: event.seconds ?? 0,
    card: event.card ?? null,
  }
  const already = shown.findIndex((candidate) => candidate.key === step.key)
  if (already < 0) {
    return [ ...shown, step ]
  }

  return shown.map((candidate) => (candidate.key === step.key ? { ...candidate, ...step } : candidate))
}
