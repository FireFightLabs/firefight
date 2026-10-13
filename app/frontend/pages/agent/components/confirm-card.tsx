import { IconAlertTriangle, IconCheck, IconChevronDown, IconX } from "@tabler/icons-react"
import { useState } from "react"

import { Button } from "@/components/agent-ui/button"
import { DetailList } from "@/components/detail-list"
import { Checkbox } from "@/components/ui/checkbox"
import { ToggleGroup, ToggleGroupItem } from "@/components/ui/toggle-group"
import { withLocalMoments } from "@/lib/formatters"
import { answerConfirmations, type ConfirmationAnswer } from "@/pages/agent/lib/chat-updates"
import type { AgentChatConfirmation } from "@/types/serializers"

interface ConfirmCardProps {
  conversationId: string
  confirmations: AgentChatConfirmation[]
}

type Answer = Omit<ConfirmationAnswer, "toolCallId">

const ALLOW_FOR_CHAT = "Allow for the rest of this chat"
const CANCELLED: Answer = { approved: false, forChat: false, expires: null }

function answerWords(answer: Answer): string {
  if (!answer.approved) {
    return "Cancelled"
  }
  return answer.forChat ? "Confirmed and allowed for the rest of this chat" : "Confirmed"
}

// Every change Halon paused on, each with what will happen first and the raw call under Details. Nothing is sent until
// every one is answered, so the agent carries on only once it knows them all. Allowing a tool for the chat answers every
// question asked about it that may be allowed, since the server approves those too.
export function ConfirmCard({ conversationId, confirmations }: ConfirmCardProps) {
  const [ answers, setAnswers ] = useState<Record<string, Answer>>({})
  const [ sent, setSent ] = useState(false)
  const [ open, setOpen ] = useState(true)
  const answered = confirmations.filter((confirmation) => answers[confirmation.toolCallId]).length

  function answer(confirmation: AgentChatConfirmation, given: Answer) {
    const alike = given.forChat
      ? confirmations.filter((other) => other.toolCallId !== confirmation.toolCallId && other.tool === confirmation.tool && other.allowable)
      : []
    const next = {
      ...answers,
      [confirmation.toolCallId]: given,
      ...Object.fromEntries(alike.map((other) => [ other.toolCallId, { approved: true, forChat: true, expires: other.chosenExpiry ?? null } ])),
    }
    setAnswers(next)
    if (confirmations.every((each) => next[each.toolCallId])) {
      setSent(true)
      answerConfirmations(conversationId, confirmations.map((each) => ({ toolCallId: each.toolCallId, ...next[each.toolCallId] })))
    }
  }

  function reopen(confirmation: AgentChatConfirmation) {
    setAnswers((current) => Object.fromEntries(Object.entries(current).filter(([ toolCallId ]) => toolCallId !== confirmation.toolCallId)))
  }

  function dismiss() {
    setOpen(false)
  }

  function show() {
    setOpen(true)
  }

  if (!open) {
    return (
      <Button size="sm" variant="secondary" onClick={show}>
        Open approval
      </Button>
    )
  }

  if (sent) {
    return (
      <span className="inline-flex w-fit items-center gap-1.5 rounded-full bg-green-tint py-1 pr-2.5 pl-1 text-[12.5px] font-medium text-green">
        <span className="flex size-4.5 items-center justify-center rounded-full bg-green text-canvas">
          <IconCheck className="size-3" stroke={3} />
        </span>
        Sent
      </span>
    )
  }

  return (
    <section className="relative flex w-full max-w-160 flex-col rounded-card bg-surface shadow-card" aria-label="Confirm before Halon goes ahead">
      <button
        type="button"
        aria-label="Dismiss"
        onClick={dismiss}
        className="primitive-icon-button absolute top-2.5 right-2.5 z-10 text-ink-3 transition-colors duration-100 hover:bg-hover hover:text-ink"
      >
        <IconX className="size-3.5" />
      </button>
      {confirmations.map((confirmation) => (
        <ConfirmQuestion
          key={confirmation.toolCallId}
          confirmation={confirmation}
          answer={answers[confirmation.toolCallId]}
          onAnswer={answer}
          onReopen={reopen}
        />
      ))}
      {answered > 0 && (
        <p className="border-t border-line px-4 py-2.5 text-[12.5px] text-ink-3">
          Halon goes on once every change here is answered.
        </p>
      )}
    </section>
  )
}

interface ConfirmQuestionProps {
  confirmation: AgentChatConfirmation
  answer: Answer | undefined
  onAnswer: (confirmation: AgentChatConfirmation, answer: Answer) => void
  onReopen: (confirmation: AgentChatConfirmation) => void
}

// One change: what will happen and where, what it does, why Halon proposes it, a warning when outside text holds this
// change's own values, when it is undone, and the buttons. The tool, what it was given and every read from outside sit
// under Details.
function ConfirmQuestion({ confirmation, answer, onAnswer, onReopen }: ConfirmQuestionProps) {
  const [ expiry, setExpiry ] = useState<string | null>(confirmation.chosenExpiry ?? null)
  const [ forChat, setForChat ] = useState(false)
  const [ detailsOpen, setDetailsOpen ] = useState(false)
  const safeguards = confirmation.safeguards.map(([ label, meta ]) => ({ label, meta }))
  const called = [ { label: "tool", meta: confirmation.tool }, ...confirmation.asked.map(([ label, meta ]) => ({ label, meta: withLocalMoments(meta) })) ]
  const reads = confirmation.readRows.map(([ label, meta ]) => ({ label, meta }))

  function chooseExpiry(value: string) {
    if (value) {
      setExpiry(value)
    }
  }

  function chooseForChat(checked: boolean | "indeterminate") {
    setForChat(checked === true)
  }

  function toggleDetails() {
    setDetailsOpen((current) => !current)
  }

  function confirm() {
    onAnswer(confirmation, { approved: true, forChat, expires: expiry })
  }

  function cancel() {
    onAnswer(confirmation, CANCELLED)
  }

  function change() {
    onReopen(confirmation)
  }

  if (answer) {
    return (
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-line px-4 py-3 pr-10 not-first:border-t">
        <h3 className="text-[14px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{confirmation.title}</h3>
        <span className="text-[12.5px] text-ink-3">{answerWords(answer)}</span>
        <Button size="xs" variant="quiet" onClick={change}>
          Change
        </Button>
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3 border-line px-4 py-3.5 not-first:border-t">
      <div className="flex flex-col gap-0.5 pr-7">
        <h3 className="text-[15px] font-semibold leading-snug text-ink [overflow-wrap:anywhere]">{confirmation.title}</h3>
        {confirmation.label && <p className="text-[12.5px] text-ink-3 [overflow-wrap:anywhere]">{confirmation.label}</p>}
      </div>
      {confirmation.summary && <p className="text-[13px] leading-relaxed text-ink-2 [overflow-wrap:anywhere]">{confirmation.summary}</p>}
      {safeguards.length > 0 && <DetailList details={safeguards} />}
      {confirmation.pagePath && (
        <a href={confirmation.pagePath} target="_blank" rel="noreferrer" className="block overflow-hidden rounded-control border border-line">
          <img src={confirmation.pagePath} alt={confirmation.pageCaption ?? confirmation.title} className="block max-h-64 w-full object-cover object-top" />
        </a>
      )}
      {confirmation.supportLead && (
        <div className="flex flex-col gap-1">
          <h4 className="text-[12.5px] font-medium text-ink-2">{confirmation.supportLead}</h4>
          <ul className="flex list-disc flex-col gap-1 pl-4 text-[13px] leading-snug text-ink marker:text-ink-3">
            {confirmation.supportPoints.map((point, index) => (
              <li key={`${point.text}:${index}`} className="[overflow-wrap:anywhere]">
                {point.text}
                {point.source && <span className="text-ink-3"> ({point.source})</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
      {confirmation.readLead && (
        <p className="flex items-start gap-1.5 text-[13px] font-medium text-warning">
          <IconAlertTriangle className="mt-0.5 size-3.5 shrink-0" />
          {confirmation.readLead}
        </p>
      )}
      {confirmation.undoLabel && (
        <div className="flex flex-col gap-1.5">
          <span id={`undo-${confirmation.toolCallId}`} className="text-[12.5px] font-medium text-ink-2">{confirmation.undoLabel}</span>
          <ToggleGroup
            type="single"
            variant="outline"
            size="sm"
            value={expiry ?? ""}
            onValueChange={chooseExpiry}
            aria-labelledby={`undo-${confirmation.toolCallId}`}
            className="flex-wrap"
          >
            {confirmation.expires.map((option) => (
              <ToggleGroupItem key={option.value} value={option.value} className="px-3 text-[12.5px] data-[state=on]:text-accent-ink">
                {option.label}
              </ToggleGroupItem>
            ))}
          </ToggleGroup>
        </div>
      )}
      {confirmation.allowable && (
        <label className="flex w-fit items-center gap-2 text-[13px] text-ink-2">
          <Checkbox checked={forChat} onCheckedChange={chooseForChat} />
          {ALLOW_FOR_CHAT}
        </label>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="primary" onClick={confirm} className="max-w-full">
          <span className="truncate">{confirmation.confirmLabel}</span>
        </Button>
        <Button size="sm" variant="secondary" onClick={cancel}>
          Cancel
        </Button>
        <button
          type="button"
          aria-expanded={detailsOpen}
          onClick={toggleDetails}
          className="ml-auto flex items-center gap-1 rounded-control px-1.5 py-1 text-[12.5px] text-ink-2 transition-colors duration-150 hover:bg-hover-2 hover:text-ink"
        >
          Details
          <IconChevronDown className={`size-3.5 transition-transform duration-150 ${detailsOpen ? "rotate-180" : ""}`} />
        </button>
      </div>
      {detailsOpen && (
        <div className="flex flex-col gap-2.5 border-t border-line pt-3">
          <DetailList details={called} />
          {confirmation.readHeading && <p className="text-[12.5px] text-ink-3">{confirmation.readHeading}</p>}
          {reads.length > 0 && <DetailList details={reads} />}
        </div>
      )}
    </div>
  )
}
