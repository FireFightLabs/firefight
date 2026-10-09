import { useForm } from "@inertiajs/react"
import { IconLoader2 } from "@tabler/icons-react"
import type { ChangeEvent, FormEvent } from "react"

import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { type CodeFixQuestion, decisionVisit } from "@/lib/code-fix-work"
import { codeAgentQuestionAnswerPath } from "@/lib/routes"

export function QuestionAnswerForm({ question, reloads }: { question: CodeFixQuestion; reloads: string[] | undefined }) {
  const { data, setData, post, processing, reset } = useForm({ answer: "" })
  const fieldId = `code-agent-answer-${question.id}`

  function write(event: ChangeEvent<HTMLTextAreaElement>) {
    setData("answer", event.target.value)
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    post(codeAgentQuestionAnswerPath(question.id), { ...decisionVisit(reloads), onSuccess: clear })
  }

  function clear() {
    reset()
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
