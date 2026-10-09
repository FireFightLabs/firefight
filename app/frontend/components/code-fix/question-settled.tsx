import {
  type CodeFixQuestion, questionAnswered, questionDefaulted, questionExpired, questionOpen,
} from "@/lib/code-fix-work"

export function QuestionSettled({ question }: { question: CodeFixQuestion }) {
  return (
    <>
      <FirstAnswer question={question} />
      {question.changedTo && (
        <p className="m-0 whitespace-pre-wrap text-fg-body [overflow-wrap:anywhere]">
          <span className="font-medium text-fg-primary">Changed to </span>
          {question.changedTo}
          <span className="text-fg-muted"> by {question.changedBy ?? "someone"}</span>
        </p>
      )}
    </>
  )
}

function FirstAnswer({ question }: { question: CodeFixQuestion }) {
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
