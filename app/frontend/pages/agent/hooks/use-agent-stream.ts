import { createConsumer } from "@rails/actioncable"
import { useEffect, useRef, useState } from "react"

import { AGENT_CARD_KINDS, AGENT_CHANNEL, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import {
  refreshCharts, refreshHeldCalls, refreshMemoryQuestions, refreshOpenChat, refreshPackRefusals, refreshPlans, refreshPullRequestNotices, refreshRuns, refreshSafeguards,
  refreshSecretEntries,
  refreshWatches,
} from "@/pages/agent/lib/chat-updates"
import { NOTHING_STREAMED, type StreamEvent, streamedSteps, streamedText, withEvent } from "@/pages/agent/lib/stream-order"
import type { AgentStream } from "@/pages/agent/types"

// If the socket drops mid turn, the answer is fetched once instead of waited for.
const RECOVERY_MS = 4000

// The server says whether an answer is owed. The page never guesses it from the last message, which the empty reply
// saved before the model answers would flip within milliseconds of the question.
export function useAgentStream(conversationId: string | null, owed: boolean): AgentStream {
  const [ ended, setEnded ] = useState(false)
  const [ streamed, setStreamed ] = useState(NOTHING_STREAMED)
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
  const dropped = useRef(false)
  const busy = owed && !ended

  useEffect(() => {
    setEnded(false)
    setStreamed(NOTHING_STREAMED)
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

    // Nothing sent while the socket was away is sent again, such as an answer that finished during a deploy, so the
    // chat is read again once it is back.
    function catchUp() {
      stopRecovery()
      if (!dropped.current) {
        return
      }

      dropped.current = false
      refreshOpenChat()
    }

    const consumer = createConsumer()
    const subscription = consumer.subscriptions.create(
      { channel: AGENT_CHANNEL, id: conversationId },
      {
        connected: catchUp,
        received(event: StreamEvent) {
          stopRecovery()
          if (event.type === AGENT_STREAM_EVENTS.THINKING) {
            setEnded(false)
          }
          if (event.type === AGENT_STREAM_EVENTS.INVESTIGATION) {
            refreshRuns()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.HELD_CALL) {
            refreshHeldCalls()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.PACK_REFUSAL) {
            refreshPackRefusals()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.SECRET_ENTRY) {
            refreshSecretEntries()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.WATCH) {
            refreshWatches()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.CODE_FIX) {
            refreshOpenChat()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.PULL_REQUEST) {
            refreshPullRequestNotices()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.PLAN) {
            refreshPlans()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.MEMORY) {
            refreshMemoryQuestions()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.SAFEGUARD) {
            refreshSafeguards()
            return
          }
          if (event.type === AGENT_STREAM_EVENTS.STEP && event.card?.kind === AGENT_CARD_KINDS.CHART) {
            refreshCharts()
          }
          setStreamed((shown) => withEvent(shown, event))
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
          dropped.current = true
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
  return { busy, owed, text: owed ? streamedText(streamed) : "", steps: owed ? streamedSteps(streamed) : [] }
}
