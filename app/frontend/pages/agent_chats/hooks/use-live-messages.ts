import { router } from "@inertiajs/react"
import { useEffect, useRef, useState } from "react"

import type { AgentChatMessage } from "@/types/serializers"

const POLL_MS = 1500
// A turn that has not landed in two minutes is not coming, so the page stops asking and says so.
const POLL_LIMIT = 80

export type TurnState = "idle" | "working" | "stalled"

// A turn runs in a job, so the page asks again until the agent has replied.
function waitingForReply(messages: AgentChatMessage[] | undefined): boolean {
  const last = messages?.[messages.length - 1]
  if (!last) {
    return false
  }
  if (last.role === "user") {
    return true
  }

  return last.tools.some((tool) => !tool.answered) || last.body.trim().length === 0
}

export function useLiveMessages(
  conversationId: string | undefined,
  messages: AgentChatMessage[] | undefined,
): TurnState {
  const [ state, setState ] = useState<TurnState>("idle")
  const polls = useRef(0)

  useEffect(() => {
    polls.current = 0
  }, [ conversationId, messages?.length ])

  useEffect(() => {
    const waiting = Boolean(conversationId) && waitingForReply(messages)
    if (!waiting) {
      setState("idle")
      return
    }
    if (polls.current >= POLL_LIMIT) {
      setState("stalled")
      return
    }

    setState("working")
    const timer = setTimeout(() => {
      polls.current += 1
      router.reload({ only: [ "messages", "conversations" ] })
    }, POLL_MS)

    return () => clearTimeout(timer)
  }, [ conversationId, messages ])

  return state
}
