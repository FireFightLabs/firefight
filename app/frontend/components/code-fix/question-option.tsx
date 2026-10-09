import { IconCheck, IconLoader2 } from "@tabler/icons-react"

import { type CodeFixQuestion, type CodeFixQuestionOption, currentChoice } from "@/lib/code-fix-work"

interface QuestionOptionProps {
  option: CodeFixQuestionOption
  index: number
  question: CodeFixQuestion
  choosable: boolean
  sending: boolean
  // Picked in a form that sends on submit rather than on the click, or undefined where a click sends it.
  selected?: boolean
  onChoose: (index: number) => void
}

export function QuestionOption({ option, index, question, choosable, sending, selected, onChoose }: QuestionOptionProps) {
  const recommended = question.recommended === index
  const chosen = currentChoice(question) === index
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
  const frame = `flex w-full min-w-0 flex-col items-start gap-0.5 rounded-md border px-2.5 py-2 text-left ${optionTone(chosen, selected)}`

  if (!choosable) {
    return <div className={frame}>{body}</div>
  }

  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={() => onChoose(index)}
      className={`${frame} transition-colors hover:border-border-strong hover:bg-surface-hover focus-visible:outline-none`}
    >
      {body}
    </button>
  )
}

// In a form only the pick stands out, and the answer it replaces keeps just its check.
function optionTone(chosen: boolean, selected: boolean | undefined): string {
  if (selected) {
    return "border-brand bg-brand-tint"
  }
  return chosen && selected === undefined ? "border-success-border bg-success-tint" : "border-border bg-background"
}
