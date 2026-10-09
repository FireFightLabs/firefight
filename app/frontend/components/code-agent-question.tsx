import { IconMessageQuestion } from "@tabler/icons-react"
import { useState } from "react"

import { QuestionChangeForm } from "@/components/code-fix/question-change-form"
import { QuestionOptions } from "@/components/code-fix/question-options"
import { QuestionSettled } from "@/components/code-fix/question-settled"
import { QuestionWaiting } from "@/components/code-fix/question-waiting"
import { Button } from "@/components/ui/button"
import { type CodeFixQuestion, questionChangeable, questionOpen } from "@/lib/code-fix-work"

interface CodeAgentQuestionProps {
  question: CodeFixQuestion
  // Why whoever is looking cannot answer, from the server, or null when they can.
  blockedReason?: string | null
  // Why whoever is looking cannot change the settled answer, from the server, or null when they can.
  changeBlockedReason?: string | null
  // Drawn before the server said who may answer, so it offers nothing yet.
  readOnly?: boolean
  // The page props an answer changes, for a page that must not be visited whole.
  reloads?: string[]
}

// A question the coding agent asked while it writes a change, under the step that runs it: the question, then each option
// with what it leads to and the one the agent recommends with why. While it waits, the person the change runs as picks
// one in a click or writes something else, unless Halon already answered. Once settled, who answered and what they chose,
// and while the change is still written, Change answer lets them pick another option or write their own.
export function CodeAgentQuestion({ question, blockedReason = null, changeBlockedReason = null, readOnly = false, reloads }: CodeAgentQuestionProps) {
  const [ changing, setChanging ] = useState(false)
  const open = questionOpen(question)
  const choosable = open && blockedReason === null && !readOnly
  const changeable = questionChangeable(question) && changeBlockedReason === null && !readOnly
  const editing = changing && changeable

  function startChanging() {
    setChanging(true)
  }

  function stopChanging() {
    setChanging(false)
  }

  return (
    <div className="flex min-w-0 flex-col gap-2 rounded-md border border-border bg-surface-selected px-2.5 py-2">
      <span className="flex items-center gap-1.5 text-fg-muted">
        <IconMessageQuestion aria-hidden className="size-3.5 shrink-0" />
        {open ? "The coding agent asks" : "The coding agent asked"}
      </span>
      <p className="m-0 whitespace-pre-wrap font-medium text-fg-primary [overflow-wrap:anywhere]">{question.text}</p>
      {editing && (
        <>
          <QuestionSettled question={question} />
          <QuestionChangeForm question={question} reloads={reloads} onDone={stopChanging} />
        </>
      )}
      {!editing && (
        <>
          {question.options.length > 0 && <QuestionOptions question={question} choosable={choosable} reloads={reloads} />}
          <QuestionSettled question={question} />
        </>
      )}
      {changeable && !editing && (
        <Button type="button" size="sm" variant="outline" className="w-fit" onClick={startChanging}>
          Change answer
        </Button>
      )}
      {open && <QuestionWaiting question={question} blockedReason={blockedReason} readOnly={readOnly} reloads={reloads} />}
    </div>
  )
}
