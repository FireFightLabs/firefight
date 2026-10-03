import ApprovalCard from "@/components/agent-ui/approval-card"
import { answerConfirmations } from "@/pages/agent/lib/chat-updates"
import type { AgentChatConfirmation } from "@/types/serializers"

interface ConfirmCardProps {
  conversationId: string
  confirmations: AgentChatConfirmation[]
}

const CONFIRM = "Confirm"
const ALLOW_FOR_CHAT = "Allow for the rest of this chat"
const CANCEL = "Cancel"
const OPTIONS = [ CONFIRM, ALLOW_FOR_CHAT, CANCEL ]

// A question left unanswered stays open, so the agent carries on only once every one is answered.
// Allowing a tool for the chat answers every question asked about it, since the server approves those too.
export function ConfirmCard({ conversationId, confirmations }: ConfirmCardProps) {
  // The agent's sentence leads when it wrote one, with the tool named above it and what it was given below.
  const questions = confirmations.map((confirmation) => ({
    q: confirmation.intent ?? confirmation.question,
    eyebrow: confirmation.intent ? confirmation.question.replace(/\?$/, "") : undefined,
    details: confirmation.asked.map(([ label, meta ]) => ({ label, meta })),
    type: "radio" as const,
    options: OPTIONS,
  }))

  function submit(answers: Record<number, number[]>) {
    const answered = confirmations.flatMap((confirmation, index) => {
      const picked = answers[index]?.[0]
      if (picked === undefined) {
        return []
      }
      const option = OPTIONS[picked]
      return [ { toolCallId: confirmation.toolCallId, approved: option !== CANCEL, forChat: option === ALLOW_FOR_CHAT } ]
    })
    answerConfirmations(conversationId, answered)
  }

  function sameTool(questionIndex: number, optionIndex: number) {
    if (OPTIONS[optionIndex] !== ALLOW_FOR_CHAT) {
      return []
    }
    const tool = confirmations[questionIndex].tool
    return confirmations.flatMap((confirmation, index) => (index !== questionIndex && confirmation.tool === tool ? [ index ] : []))
  }

  return (
    <ApprovalCard
      key={confirmations.map((confirmation) => confirmation.toolCallId).join(" ")}
      questions={questions}
      allowCustom={false}
      resettable={false}
      wide
      answerAlike={sameTool}
      labels={{ sentMessage: "Sent", send: "Send", skip: "Skip" }}
      onSubmitted={submit}
    />
  )
}
