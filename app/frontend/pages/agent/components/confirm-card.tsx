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

// One answer on the card: whether it confirms, allows the tool for the chat, and when a change customers feel is undone.
interface Choice {
  label: string
  approved: boolean
  forChat: boolean
  expires: string | null
}

// A change customers feel is confirmed with when it is undone, each time offered as its own answer with the default
// first. Allow for the rest of the chat is offered only where the server says it may be, never once Halon read anything
// from outside, nor for a statement that writes rows.
function choicesFor(confirmation: AgentChatConfirmation): Choice[] {
  const confirming = confirmation.expires.length > 0
    ? confirmation.expires.map((expiry) => ({ label: `${CONFIRM}, ${expiry.label.toLowerCase()}`, approved: true, forChat: false, expires: expiry.value }))
    : [ { label: CONFIRM, approved: true, forChat: false, expires: null } ]
  const allowing = confirmation.allowable
    ? [ { label: ALLOW_FOR_CHAT, approved: true, forChat: true, expires: confirmation.expires[0]?.value ?? null } ]
    : []
  return [ ...confirming, ...allowing, { label: CANCEL, approved: false, forChat: false, expires: null } ]
}

// A call through a connection leads with what it reaches, worked out from the tool, then the call, with the agent's
// sentence quieter below, since the agent's words can name another account than the one the tool reaches. Any other
// call leads with the agent's sentence when it wrote one, with the tool named above it. What the call touches beyond its
// arguments, such as the rows it changes, comes before what it was given, and what Halon read from outside before asking
// comes last as a warning.
function questionFor(confirmation: AgentChatConfirmation, choices: Choice[]): ApprovalQuestion {
  const details = [ ...confirmation.safeguards, ...confirmation.asked ].map(([ label, meta ]) => ({ label, meta }))
  const caution = confirmation.readLead
  const cautionDetails = confirmation.readRows.map(([ label, meta ]) => ({ label, meta }))
  const options = choices.map((choice) => choice.label)
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
  const choices = confirmations.map(choicesFor)
  const questions = confirmations.map((confirmation, index) => questionFor(confirmation, choices[index]))

  function submit(answers: Record<number, number[]>) {
    const answered = confirmations.flatMap((confirmation, index) => {
      const picked = answers[index]?.[0]
      const choice = picked === undefined ? undefined : choices[index][picked]
      if (!choice) {
        return []
      }
      return [ { toolCallId: confirmation.toolCallId, approved: choice.approved, forChat: choice.forChat, expires: choice.expires } ]
    })
    answerConfirmations(conversationId, answered)
  }

  function sameTool(questionIndex: number, optionIndex: number) {
    if (!choices[questionIndex][optionIndex]?.forChat) {
      return []
    }
    const tool = confirmations[questionIndex].tool
    return confirmations.flatMap((confirmation, index) => {
      const allowAt = choices[index].findIndex((choice) => choice.forChat)
      return index !== questionIndex && confirmation.tool === tool && allowAt >= 0 ? [ [ index, allowAt ] as const ] : []
    })
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
