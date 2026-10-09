import { useForm } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"
import type { ChangeEvent, FormEvent } from "react"

import { QuestionOption } from "@/components/code-fix/question-option"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { type CodeFixQuestion, currentChoice, decisionVisit } from "@/lib/code-fix-work"
import { codeAgentQuestionChangePath } from "@/lib/routes"

interface QuestionChangeFormProps {
  question: CodeFixQuestion
  reloads: string[] | undefined
  onDone: () => void
}

interface ChangeData {
  option: number | null
  answer: string
}

// Another option or the person's own words, one or the other, sent to the coding agent in place of the earlier answer.
export function QuestionChangeForm({ question, reloads, onDone }: QuestionChangeFormProps) {
  const { data, setData, post, processing } = useForm<ChangeData>({ option: null, answer: "" })
  const fieldId = `code-agent-change-${question.id}`
  const written = data.answer.trim().length > 0
  const sendable = (data.option !== null && data.option !== currentChoice(question)) || written

  function pick(index: number) {
    setData({ option: index, answer: "" })
  }

  function write(event: ChangeEvent<HTMLTextAreaElement>) {
    setData({ option: null, answer: event.target.value })
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    post(codeAgentQuestionChangePath(question.id), { ...decisionVisit(reloads), onSuccess: onDone })
  }

  return (
    <form onSubmit={submit} className="flex flex-col gap-2">
      {question.options.length > 0 && (
        <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
          {question.options.map((option, index) => (
            <li key={index}>
              <QuestionOption
                option={option}
                index={index}
                question={question}
                choosable={!processing}
                sending={false}
                selected={data.option === index}
                onChoose={pick}
              />
            </li>
          ))}
        </ul>
      )}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={fieldId} className="text-[12px]">{question.options.length > 0 ? "Or write your own answer" : "Your new answer"}</Label>
        <Textarea id={fieldId} rows={2} className="resize-none bg-background text-[12px]" value={data.answer} onChange={write} />
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="text-fg-muted">The coding agent is sent this in place of the earlier answer.</span>
        <span className="flex items-center gap-2">
          <Button type="button" size="sm" variant="outline" onClick={onDone} disabled={processing}>
            Cancel
          </Button>
          <Button type="submit" size="sm" disabled={processing || !sendable}>
            {processing && <IconLoader2 className="motion-safe:animate-spin" />}
            Submit
          </Button>
        </span>
      </div>
    </form>
  )
}
