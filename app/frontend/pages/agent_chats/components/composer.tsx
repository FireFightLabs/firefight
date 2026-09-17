import { router } from "@inertiajs/react"
import { IconArrowUp } from "@tabler/icons-react"
import { useState } from "react"

import { agentChatAskPath } from "@/lib/routes"

interface ComposerProps {
  conversationId?: string
  busy: boolean
}

export function Composer({ conversationId, busy }: ComposerProps) {
  const [question, setQuestion] = useState("")

  function send() {
    if (busy || !conversationId || question.trim().length === 0) {
      return
    }

    router.post(agentChatAskPath(conversationId), { question }, { preserveScroll: true })
    setQuestion("")
  }

  function sendOnEnter(event: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key !== "Enter" || event.shiftKey) {
      return
    }
    event.preventDefault()
    send()
  }

  function placeholder() {
    if (!conversationId) {
      return "Start a chat first"
    }
    if (busy) {
      return "The agent is working"
    }

    return "Ask the agent"
  }

  return (
    <div className="mx-auto flex w-full max-w-2xl items-end gap-2 rounded-window bg-field p-2 shadow-hairline">
      <textarea
        value={question}
        onChange={(event) => setQuestion(event.target.value)}
        onKeyDown={sendOnEnter}
        rows={2}
        disabled={!conversationId}
        placeholder={placeholder()}
        className="min-h-10 flex-1 resize-none bg-transparent px-2 py-1.5 text-[13.5px] text-ink outline-none placeholder:text-ink-3"
      />
      <button
        type="button"
        onClick={send}
        disabled={busy || !conversationId || question.trim().length === 0}
        aria-label="Send"
        className="flex size-8 items-center justify-center rounded-control bg-accent text-accent-ink shadow-btn transition-opacity duration-100 disabled:opacity-40"
      >
        <IconArrowUp className="size-4" />
      </button>
    </div>
  )
}
