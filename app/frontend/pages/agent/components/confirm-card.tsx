import ApprovalCard from "@/components/agent-ui/approval-card"
import { answerConfirmations } from "@/pages/agent/lib/chat-updates"
import type { AgentChatConfirmation } from "@/types/serializers"

interface ConfirmCardProps {
  conversationId: string
  confirmations: AgentChatConfirmation[]
}

const CONFIRM = "Confirm"
const CANCEL = "Cancel"
const OPTIONS = [ CONFIRM, CANCEL ]

// A question left unanswered stays open, so the agent carries on only once every one is answered.
export function ConfirmCard({ conversationId, confirmations }: ConfirmCardProps) {
  const questions = confirmations.map((confirmation) => ({
    q: confirmation.question,
    details: confirmation.asked.map(([ label, meta ]) => ({ label, meta })),
    type: "radio" as const,
    options: OPTIONS,
  }))

  function submit(answers: Record<number, number[]>) {
    const answered = confirmations.flatMap((confirmation, index) => {
      const picked = answers[index]?.[0]
      return picked === undefined ? [] : [ { toolCallId: confirmation.toolCallId, approved: OPTIONS[picked] === CONFIRM } ]
    })
    answerConfirmations(conversationId, answered)
  }

  return (
    <ApprovalCard
      key={confirmations.map((confirmation) => confirmation.toolCallId).join(" ")}
      questions={questions}
      allowCustom={false}
      resettable={false}
      labels={{ sentMessage: "Sent", send: "Send", skip: "Skip" }}
      onSubmitted={submit}
    />
  )
}
