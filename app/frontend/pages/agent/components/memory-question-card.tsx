import { router } from "@inertiajs/react"
import { IconBrain, IconCheck, IconExternalLink, IconLoader2 } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { DecideMemoryDialog, DECISIONS } from "@/components/memory/decide-memory-dialog"
import { MEMORY_QUERY_PARAM } from "@/lib/generated/constants"
import { confirmMemoryPath, memoryPath, rejectMemoryPath } from "@/lib/routes"
import { askedAboutMemory } from "@/pages/agent/lib/memory-question"
import type { AgentChatMemoryQuestion } from "@/types/serializers"

interface MemoryQuestionCardProps {
  question: AgentChatMemoryQuestion
}

const IN_PLACE = { preserveScroll: true, preserveState: true }

// Something Halon read contradicted a memory, so it asks the person which is right while they still have the context.
// Still right keeps the memory, Not right takes what Halon read instead, and Correct says what is right instead of both.
// The server ships whether each answer is open, and how it was settled once it was.
export function MemoryQuestionCard({ question }: MemoryQuestionCardProps) {
  const [ sending, setSending ] = useState(false)
  const [ correcting, setCorrecting ] = useState(false)
  const memoryId = question.memoryId ?? null
  const waiting = memoryId !== null && !question.decided
  const blocked = question.confirmBlockedReason ?? question.rejectBlockedReason ?? null
  const correction = correcting && memoryId && question.remembered ? { id: memoryId, text: question.remembered } : null

  function doneSending() {
    setSending(false)
  }

  function keep() {
    if (memoryId) {
      setSending(true)
      router.post(confirmMemoryPath(memoryId), {}, { ...IN_PLACE, onFinish: doneSending })
    }
  }

  function reject() {
    if (memoryId) {
      setSending(true)
      router.post(rejectMemoryPath(memoryId), {}, { ...IN_PLACE, onFinish: doneSending })
    }
  }

  function openCorrection() {
    setCorrecting(true)
  }

  function closeCorrection() {
    setCorrecting(false)
  }

  return (
    <section className="flex w-full max-w-160 flex-col gap-3 rounded-card bg-surface px-4 py-3.5 shadow-card" aria-label="Which is right">
      <div className="flex items-start gap-2">
        {question.decided ? <IconCheck className="mt-0.5 size-4 shrink-0 text-success" /> : <IconBrain className="mt-0.5 size-4 shrink-0 text-warning" />}
        <h3 className="text-[14px] font-semibold leading-snug text-ink">Which is right?</h3>
      </div>
      <p className="text-[13px] leading-relaxed text-ink [overflow-wrap:anywhere]">{askedAboutMemory(question)}</p>
      {question.decided && <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">{question.decided}</p>}
      {memoryId === null && <p className="text-[12.5px] text-ink-3">Someone deleted this memory on the Memory page.</p>}
      <div className="flex flex-wrap items-center gap-2">
        {waiting && (
          <>
            <Button size="sm" variant="primary" disabled={Boolean(question.confirmBlockedReason) || sending} onClick={keep}>
              {sending && <IconLoader2 className="size-3.5 motion-safe:animate-spin" />}
              Still right
            </Button>
            <Button size="sm" disabled={Boolean(question.rejectBlockedReason) || sending} onClick={reject}>
              Not right
            </Button>
            <Button size="sm" disabled={Boolean(question.rejectBlockedReason) || sending} onClick={openCorrection}>
              Correct
            </Button>
          </>
        )}
        {memoryId && (
          <a href={memoryPath({ [MEMORY_QUERY_PARAM]: memoryId })} className="flex items-center gap-1 text-[12.5px] font-medium text-ink-2 hover:text-ink">
            <IconExternalLink className="size-3.5" />
            Open on the Memory page
          </a>
        )}
      </div>
      {waiting && blocked && <p className="text-[12.5px] text-ink-3">{blocked}</p>}
      <DecideMemoryDialog
        key={correcting ? "correcting" : "closed"}
        memory={correction}
        decision={DECISIONS.CORRECT}
        onClose={closeCorrection}
      />
    </section>
  )
}
