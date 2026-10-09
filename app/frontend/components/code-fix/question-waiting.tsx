import { IconClock } from "@tabler/icons-react"

import { QuestionAnswerForm } from "@/components/code-fix/question-answer-form"
import { useExpiresIn } from "@/hooks/use-expires-in"
import type { CodeFixQuestion } from "@/lib/code-fix-work"

interface QuestionWaitingProps {
  question: CodeFixQuestion
  blockedReason: string | null
  readOnly: boolean
  reloads: string[] | undefined
}

export function QuestionWaiting({ question, blockedReason, readOnly, reloads }: QuestionWaitingProps) {
  const expiry = useExpiresIn(question.answerDueAt)

  return (
    <>
      {blockedReason && <p className="m-0 text-fg-muted">{blockedReason}</p>}
      {!blockedReason && !readOnly && <QuestionAnswerForm question={question} reloads={reloads} />}
      {expiry.label && (
        <span className="flex items-center gap-1 text-fg-muted">
          <IconClock aria-hidden className="size-3.5 shrink-0" />
          {expiry.label}.{question.timeoutOutcome && ` If nobody answers by then, ${question.timeoutOutcome}.`}
        </span>
      )}
    </>
  )
}
