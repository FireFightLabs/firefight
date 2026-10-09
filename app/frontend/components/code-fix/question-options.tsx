import { router } from "@inertiajs/react"
import { useState } from "react"

import { QuestionOption } from "@/components/code-fix/question-option"
import { type CodeFixQuestion, decisionVisit } from "@/lib/code-fix-work"
import { codeAgentQuestionAnswerPath } from "@/lib/routes"

interface QuestionOptionsProps {
  question: CodeFixQuestion
  choosable: boolean
  reloads: string[] | undefined
}

// An option is keyed by its place, which is also how an answer names it, since two options can share a label.
export function QuestionOptions({ question, choosable, reloads }: QuestionOptionsProps) {
  const [ sending, setSending ] = useState<number | null>(null)

  function choose(index: number) {
    setSending(index)
    router.post(codeAgentQuestionAnswerPath(question.id), { option: index }, { ...decisionVisit(reloads), onFinish: doneSending })
  }

  function doneSending() {
    setSending(null)
  }

  return (
    <ul className="m-0 flex list-none flex-col gap-1.5 p-0">
      {question.options.map((option, index) => (
        <li key={index}>
          <QuestionOption
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
