import ApprovalCard, { type ApprovalQuestion } from "@/components/agent-ui/approval-card"
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

// A call through a connection leads with what it reaches, worked out from the tool, then the call, with the agent's
// sentence quieter below, since the agent's words can name another account than the one the tool reaches. Any other
// call leads with the agent's sentence when it wrote one, with the tool named above it. What it was given comes last.
function questionFor(confirmation: AgentChatConfirmation): ApprovalQuestion {
  const details = confirmation.asked.map(([ label, meta ]) => ({ label, meta }))
  if (confirmation.target) {
    return { q: confirmation.target, subtitle: confirmation.callName, note: confirmation.intent, details, type: "radio", options: OPTIONS }
  }
  return {
    q: confirmation.intent ?? confirmation.question,
    eyebrow: confirmation.intent ? confirmation.question.replace(/\?$/, "") : undefined,
    details,
    type: "radio",
    options: OPTIONS,
  }
}

// A question left unanswered stays open, so the agent carries on only once every one is answered.
// Allowing a tool for the chat answers every question asked about it, since the server approves those too.
export function ConfirmCard({ conversationId, confirmations }: ConfirmCardProps) {
  const questions = confirmations.map(questionFor)

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
