import { router, useForm } from "@inertiajs/react"
import { IconCheck, IconClock, IconLoader2, IconMessageQuestion } from "@tabler/icons-react"
import { type ChangeEvent, type FormEvent, useState } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { useExpiresIn } from "@/hooks/use-expires-in"
import {
  type CodeFixQuestion, type CodeFixQuestionOption, questionAnswered, questionDefaulted, questionExpired, questionOpen,
} from "@/lib/code-fix-work"
import { codeAgentQuestionAnswerPath } from "@/lib/routes"

interface CodeAgentQuestionProps {
  question: CodeFixQuestion
  // Why whoever is looking cannot answer, from the server, or null when they can.
  blockedReason?: string | null
}

// A question the coding agent asked while it writes a change, under the step that runs it: the question, then each option
// with what it leads to and the one the agent recommends with why. While it waits, the person the change runs as picks
// one in a click or writes something else, unless Halon already answered. Once settled, who answered and what they chose.
export function CodeAgentQuestion({ question, blockedReason = null }: CodeAgentQuestionProps) {
  const open = questionOpen(question)
  const choosable = open && blockedReason === null

  return (
    <div className="flex min-w-0 flex-col gap-2 rounded-md border border-border bg-surface-selected px-2.5 py-2">
      <span className="flex items-center gap-1.5 text-fg-muted">
        <IconMessageQuestion aria-hidden className="size-3.5 shrink-0" />
        {open ? "The coding agent asks" : "The coding agent asked"}
      </span>
      <p className="m-0 whitespace-pre-wrap font-medium text-fg-primary [overflow-wrap:anywhere]">{question.text}</p>
      {question.options.length > 0 && <Options question={question} choosable={choosable} />}
      <Settled question={question} />
      {open && <Waiting question={question} blockedReason={blockedReason} />}
    </div>
  )
}

function Options({ question, choosable }: { question: CodeFixQuestion; choosable: boolean }) {
  const [ sending, setSending ] = useState<number | null>(null)

  function choose(index: number) {
    setSending(index)
    router.post(codeAgentQuestionAnswerPath(question.id), { option: index }, { preserveScroll: true, onFinish: () => setSending(null) })
  }

  return (
    <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
      {question.options.map((option, index) => (
        <li key={option.label}>
          <OptionChoice
            option={option}
            index={index}
            question={question}
            choosable={choosable && sending === null}
            sending={sending === index}
            onChoose={choose}
          />
        </li>
      ))}
    </ul>
  )
}

interface OptionChoiceProps {
  option: CodeFixQuestionOption
  index: number
  question: CodeFixQuestion
  choosable: boolean
  sending: boolean
  onChoose: (index: number) => void
}

function OptionChoice({ option, index, question, choosable, sending, onChoose }: OptionChoiceProps) {
  const recommended = question.recommended === index
  const chosen = question.chosen === index
  const body = (
    <>
      <span className="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5">
        {chosen && <IconCheck aria-hidden className="size-3.5 shrink-0 text-success" />}
        {sending && <IconLoader2 aria-hidden className="size-3.5 shrink-0 motion-safe:animate-spin" />}
        <span className="font-semibold text-fg-primary [overflow-wrap:anywhere]">{option.label}</span>
        {recommended && <span className="rounded-full border border-brand-border bg-brand-tint px-1.5 text-[11px] font-medium text-brand">Recommended</span>}
      </span>
      <span className="text-fg-body [overflow-wrap:anywhere]">{option.consequence}</span>
      {recommended && question.recommendedReason && <span className="text-fg-muted [overflow-wrap:anywhere]">{question.recommendedReason}</span>}
    </>
  )
  const frame = `flex w-full min-w-0 flex-col items-start gap-0.5 rounded-md border px-2.5 py-2 text-left ${chosen ? "border-success-border bg-success-tint" : "border-border bg-background"}`

  if (!choosable) {
    return <div className={frame}>{body}</div>
  }

  return (
    <button type="button" onClick={() => onChoose(index)} className={`${frame} transition-colors hover:border-border-strong hover:bg-surface-hover focus-visible:outline-none`}>
      {body}
    </button>
  )
}

function Settled({ question }: { question: CodeFixQuestion }) {
  if (questionAnswered(question)) {
    const chosen = question.chosen === null ? undefined : question.options[question.chosen]
    return (
      <p className="m-0 whitespace-pre-wrap text-fg-body [overflow-wrap:anywhere]">
        <span className="font-medium text-fg-primary">{question.answeredBy ?? "Someone"} {chosen ? "chose" : "answered"}: </span>
        {chosen ? chosen.label : question.answer}
      </p>
    )
  }
  if (questionDefaulted(question)) {
    return <p className="m-0 text-fg-body">Nobody answered in time, so the change went with the recommendation.</p>
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
  const fallback = question.recommended === null ? "the change stops" : "the change goes with the recommendation"

  return (
    <>
      {blockedReason ? <p className="m-0 text-fg-muted">{blockedReason}</p> : <AnswerForm question={question} />}
      {expiry.label && (
        <span className="flex items-center gap-1 text-fg-muted">
          <IconClock aria-hidden className="size-3.5 shrink-0" />
          {expiry.label}. If nobody answers by then, {fallback}.
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
      <Label htmlFor={fieldId} className="text-[12px]">{question.options.length > 0 ? "Something else" : "Your answer"}</Label>
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
