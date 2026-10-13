import { createConsumer } from "@rails/actioncable"
import { useEffect, useRef, useState } from "react"

import { NOTHING_STREAMED, type StreamEvent, streamedSteps, streamedText, withEvent } from "@/lib/agent-chat/stream-order"
import type { AgentStream } from "@/lib/agent-chat/types"
import { AGENT_CHANNEL, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"

// If the socket drops mid turn, the answer is fetched once instead of waited for.
const RECOVERY_MS = 4000

const ENDING_EVENTS: string[] = [ AGENT_STREAM_EVENTS.ANSWERED, AGENT_STREAM_EVENTS.FAILED, AGENT_STREAM_EVENTS.WAITING ]

export interface ChatStreamHandlers {
  // Reads the chat again: when a turn ends, when the socket comes back after missing something, and when it dropped mid turn.
  reloadChat: () => void
  // An event that only says something changed elsewhere in the chat, such as a watch or a held call. True when it was
  // handled that way, so it is not drawn into the turn.
  onNotice?: (event: StreamEvent) => boolean
  // Every event drawn into the turn, after it is drawn.
  onStreamed?: (event: StreamEvent) => void
}

// A chat's live turn, from any page that shows one. The server says whether an answer is owed. The page never guesses it
// from the last message, which the empty reply saved before the model answers would flip within milliseconds of the question.
export function useChatStream(conversationId: string | null, owed: boolean, handlers: ChatStreamHandlers): AgentStream {
  const [ ended, setEnded ] = useState(false)
  const [ streamed, setStreamed ] = useState(NOTHING_STREAMED)
  const working = useRef(false)
  const recovery = useRef<number | undefined>(undefined)
  const dropped = useRef(false)
  const latest = useRef(handlers)
  const busy = owed && !ended

  useEffect(() => {
    latest.current = handlers
  }, [ handlers ])

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

    function reloadChat() {
      latest.current.reloadChat()
    }

    // Nothing sent while the socket was away is sent again, such as an answer that finished during a deploy, so the
    // chat is read again once it is back.
    function catchUp() {
      stopRecovery()
      if (!dropped.current) {
        return
      }

      dropped.current = false
      reloadChat()
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
          if (latest.current.onNotice?.(event)) {
            return
          }
          setStreamed((shown) => withEvent(shown, event))
          latest.current.onStreamed?.(event)
          if (ENDING_EVENTS.includes(event.type)) {
            setEnded(true)
            reloadChat()
          }
        },
        disconnected() {
          dropped.current = true
          if (!working.current) {
            return
          }

          recovery.current = window.setTimeout(reloadChat, RECOVERY_MS)
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
