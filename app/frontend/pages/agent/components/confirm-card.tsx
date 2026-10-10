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
// Once Halon has read anything from outside, a change is confirmed one at a time, so the chat-wide allow is not offered.
const OPTIONS_ONE_AT_A_TIME = [ CONFIRM, CANCEL ]

function optionsFor(confirmation: AgentChatConfirmation) {
  return confirmation.allowable ? OPTIONS : OPTIONS_ONE_AT_A_TIME
}

// A call through a connection leads with what it reaches, worked out from the tool, then the call, with the agent's
// sentence quieter below, since the agent's words can name another account than the one the tool reaches. Any other
// call leads with the agent's sentence when it wrote one, with the tool named above it. What it was given comes next,
// and what Halon read from outside before asking comes last as a warning.
function questionFor(confirmation: AgentChatConfirmation): ApprovalQuestion {
  const details = confirmation.asked.map(([ label, meta ]) => ({ label, meta }))
  const caution = confirmation.readLead
  const cautionDetails = confirmation.readRows.map(([ label, meta ]) => ({ label, meta }))
  const options = optionsFor(confirmation)
  if (confirmation.target) {
    return { q: confirmation.target, subtitle: confirmation.callName, note: confirmation.intent, details, caution, cautionDetails, type: "radio", options }
  }
  return {
    q: confirmation.intent ?? confirmation.question,
    eyebrow: confirmation.intent ? confirmation.toolLabel : undefined,
    details,
    caution,
    cautionDetails,
    type: "radio",
    options,
  }
}

// A question left unanswered stays open, so the agent carries on only once every one is answered.
// Allowing a tool for the chat answers every question asked about it that may be allowed, since the server approves those too.
export function ConfirmCard({ conversationId, confirmations }: ConfirmCardProps) {
  const questions = confirmations.map(questionFor)

  function submit(answers: Record<number, number[]>) {
    const answered = confirmations.flatMap((confirmation, index) => {
      const picked = answers[index]?.[0]
      if (picked === undefined) {
        return []
      }
      const option = optionsFor(confirmation)[picked]
      return [ { toolCallId: confirmation.toolCallId, approved: option !== CANCEL, forChat: option === ALLOW_FOR_CHAT } ]
    })
    answerConfirmations(conversationId, answered)
  }

  function sameTool(questionIndex: number, optionIndex: number) {
    const asked = confirmations[questionIndex]
    if (optionsFor(asked)[optionIndex] !== ALLOW_FOR_CHAT) {
      return []
    }
    return confirmations.flatMap((confirmation, index) => (
      index !== questionIndex && confirmation.allowable && confirmation.tool === asked.tool ? [ index ] : []
    ))
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
