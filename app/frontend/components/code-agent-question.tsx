import { useForm } from "@inertiajs/react"
import { IconClock, IconLoader2, IconMessageQuestion } from "@tabler/icons-react"
import type { ChangeEvent, FormEvent } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { useExpiresIn } from "@/hooks/use-expires-in"
import { type CodeFixQuestion, questionAnswered, questionExpired, questionOpen } from "@/lib/code-fix-work"
import { codeAgentQuestionAnswerPath } from "@/lib/routes"

interface CodeAgentQuestionProps {
  question: CodeFixQuestion
  // Why whoever is looking cannot answer, from the server, or null when they can.
  blockedReason?: string | null
}

// A question the coding agent asked while it writes a change, under the step that runs it. While it waits, the person
// the change runs as answers it here, unless Halon already did. Once settled, who answered and what they said.
export function CodeAgentQuestion({ question, blockedReason = null }: CodeAgentQuestionProps) {
  return (
    <div className="flex min-w-0 flex-col gap-1.5 rounded-md border border-border bg-surface-selected px-2.5 py-2">
      <span className="flex items-center gap-1.5 font-medium text-fg-primary">
        <IconMessageQuestion aria-hidden className="size-3.5 shrink-0" />
        {questionOpen(question) ? "The coding agent asks" : "The coding agent asked"}
      </span>
      <p className="m-0 whitespace-pre-wrap text-fg-body [overflow-wrap:anywhere]">{question.text}</p>
      <Settled question={question} />
      {questionOpen(question) && <Waiting question={question} blockedReason={blockedReason} />}
    </div>
  )
}

function Settled({ question }: { question: CodeFixQuestion }) {
  if (questionAnswered(question)) {
    return (
      <p className="m-0 whitespace-pre-wrap text-fg-body [overflow-wrap:anywhere]">
        <span className="font-medium text-fg-primary">{question.answeredBy ?? "Someone"} answered: </span>
        {question.answer}
      </p>
    )
  }
  if (questionExpired(question)) {
    return <p className="m-0 font-medium text-error">Nobody answered in time, so the change stopped.</p>
  }
  if (!questionOpen(question)) {
    return <p className="m-0 text-fg-muted">The change ended before anyone answered.</p>
  }
  return null
}

function Waiting({ question, blockedReason }: { question: CodeFixQuestion; blockedReason: string | null }) {
  const expiry = useExpiresIn(question.answerDueAt)

  return (
    <>
      {blockedReason ? <p className="m-0 text-fg-muted">{blockedReason}</p> : <AnswerForm question={question} />}
      {expiry.label && (
        <span className="flex items-center gap-1 text-fg-muted">
          <IconClock aria-hidden className="size-3.5 shrink-0" />
          {expiry.label}. If nobody answers by then, the change stops.
        </span>
      )}
    </>
  )
}

function AnswerForm({ question }: { question: CodeFixQuestion }) {
  const { data, setData, post, processing, reset } = useForm({ answer: "" })
  const fieldId = `code-agent-answer-${question.id}`

  function write(event: ChangeEvent<HTMLTextAreaElement>) {
    setData("answer", event.target.value)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    post(codeAgentQuestionAnswerPath(question.id), { preserveScroll: true, onSuccess: () => reset() })
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-1.5">
      <Label htmlFor={fieldId} className="text-[12px]">Your answer</Label>
      <Textarea id={fieldId} rows={2} className="resize-none bg-background text-[12px]" value={data.answer} onChange={write} />
      <div className="flex items-center justify-between gap-3">
        <span className="text-fg-muted">The coding agent carries on with it.</span>
        <Button type="submit" size="sm" disabled={processing || data.answer.trim().length === 0}>
          {processing && <IconLoader2 className="motion-safe:animate-spin" />}
          Send answer
        </Button>
      </div>
    </form>
  )
}
