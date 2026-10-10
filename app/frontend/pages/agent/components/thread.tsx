import { Fragment, useEffect, useMemo, useRef, useState } from "react"

import LoadingState from "@/components/agent-ui/loading-state"
import { whenClosed } from "@/lib/handlers"
import { ConfirmCard } from "@/pages/agent/components/confirm-card"
import { HeldCalls } from "@/pages/agent/components/held-calls"
import { MemoryQuestions } from "@/pages/agent/components/memory-questions"
import { PackRefusals } from "@/pages/agent/components/pack-refusals"
import { Plans } from "@/pages/agent/components/plans"
import { PullRequestNotices } from "@/pages/agent/components/pull-request-notices"
import { Safeguards } from "@/pages/agent/components/safeguards"
import { SecretEntries } from "@/pages/agent/components/secret-entries"
import { Watches } from "@/pages/agent/components/watches"
import { WaitingMessage } from "@/pages/agent/components/waiting-message"
import { ImageDialog } from "@/components/image-dialog"
import { Message } from "@/pages/agent/components/message"
import { BEFORE_ALL_TURNS, groupedTurns, liveTurn, placeAfterTurns, settledMessages } from "@/pages/agent/lib/group-turns"
import { type AgentStream, type ChatTurn, TURN_KINDS } from "@/pages/agent/types"
import type {
  AgentChatAttachment, AgentChatConfirmation, AgentChatDataRepair, AgentChatHeldCall, AgentChatMemoryQuestion, AgentChatMessage, AgentChatMitigation,
  AgentChatOwnerAsk, AgentChatPackRefusal, AgentChatPlan, AgentChatPullRequestNotice, AgentChatSecretEntry, AgentChatWaitingMessage, AgentChatWatch,
  AgentChatWatchUpdate, ChatCompaction,
} from "@/types/serializers"

interface ThreadProps {
  conversationId: string | null
  confirmations: AgentChatConfirmation[]
  messages: AgentChatMessage[]
  compactions: ChatCompaction[]
  heldCalls: AgentChatHeldCall[]
  packRefusals: AgentChatPackRefusal[]
  secretEntries: AgentChatSecretEntry[]
  watches: AgentChatWatch[]
  watchUpdates: AgentChatWatchUpdate[]
  pullRequestNotices: AgentChatPullRequestNotice[]
  memoryQuestions: AgentChatMemoryQuestion[]
  plans: AgentChatPlan[]
  dataRepairs: AgentChatDataRepair[]
  mitigations: AgentChatMitigation[]
  ownerAsks: AgentChatOwnerAsk[]
  waiting: AgentChatWaitingMessage[]
  stream: AgentStream
}

export function Thread({
  conversationId, confirmations, messages, compactions, heldCalls, packRefusals, secretEntries, watches, watchUpdates, pullRequestNotices, memoryQuestions, plans,
  dataRepairs, mitigations, ownerAsks, waiting, stream,
}: ThreadProps) {
  const foot = useRef<HTMLDivElement>(null)
  const turns = useMemo(() => groupedTurns(settledMessages(messages, stream.owed), compactions), [ messages, compactions, stream.owed ])
  const live = liveTurn(stream, messages, compactions)
  // A held call sits where it last had news, so an approval that came in later shows where the person will look.
  const held = useMemo(() => placeAfterTurns(turns, messages, heldCalls), [ turns, messages, heldCalls ])
  // A refusal sits after the turn it happened in.
  const refused = useMemo(() => placeAfterTurns(turns, messages, packRefusals), [ turns, messages, packRefusals ])
  // A secret to type or reveal sits after the turn whose call asked for it.
  const handed = useMemo(() => placeAfterTurns(turns, messages, secretEntries), [ turns, messages, secretEntries ])
  // A watch sits after the answer that started it, and each line it said later sits where it was said.
  const watched = useMemo(() => placeAfterTurns(turns, messages, watches), [ turns, messages, watches ])
  const said = useMemo(() => placeAfterTurns(turns, messages, watchUpdates), [ turns, messages, watchUpdates ])
  // A pull request Halon opened sits where Halon said it needs attention.
  const noticed = useMemo(() => placeAfterTurns(turns, messages, pullRequestNotices), [ turns, messages, pullRequestNotices ])
  // A memory something contradicted sits after the turn that found it, while the person still has the context.
  const asked = useMemo(() => placeAfterTurns(turns, messages, memoryQuestions), [ turns, messages, memoryQuestions ])
  // A plan sits where it last moved, so a checklist that moves on stays where the person is reading.
  const planned = useMemo(() => placeAfterTurns(turns, messages, plans), [ turns, messages, plans ])
  // What Firefight did around a change sits after the turn that made it, and an owner's answer where it was asked.
  const repaired = useMemo(() => placeAfterTurns(turns, messages, dataRepairs), [ turns, messages, dataRepairs ])
  const mitigated = useMemo(() => placeAfterTurns(turns, messages, mitigations), [ turns, messages, mitigations ])
  const owned = useMemo(() => placeAfterTurns(turns, messages, ownerAsks), [ turns, messages, ownerAsks ])
  // Held by id rather than by the message, which the server's copy replaces once it answers.
  const [ openImageId, setOpenImageId ] = useState<string | null>(null)
  const openImage = sentAttachments(turns, waiting).find((attachment) => attachment.id === openImageId) ?? null

  function closeImage() {
    setOpenImageId(null)
  }

  useEffect(() => {
    foot.current?.scrollIntoView({ block: "end" })
  }, [
    messages.length, waiting.length, stream.text, stream.steps.length, heldCalls.length, packRefusals.length, secretEntries.length, watchUpdates.length, pullRequestNotices.length,
    memoryQuestions.length, plans.length, dataRepairs.length, mitigations.length, ownerAsks.length,
  ])

  return (
    <div className="min-h-0 flex-1 overflow-y-auto px-4 py-8 [mask-image:linear-gradient(to_bottom,transparent,black_16px,black_calc(100%-32px),transparent)] [scrollbar-color:var(--line-strong)_transparent] [scrollbar-width:thin]">
      <div className="mx-auto flex max-w-3xl flex-col gap-8">
        {conversationId && <HeldCalls conversationId={conversationId} heldCalls={held.get(BEFORE_ALL_TURNS)} />}
        {conversationId && <PackRefusals conversationId={conversationId} refusals={refused.get(BEFORE_ALL_TURNS)} />}
        {conversationId && <SecretEntries conversationId={conversationId} entries={handed.get(BEFORE_ALL_TURNS)} />}
        {conversationId && <Watches conversationId={conversationId} watches={watched.get(BEFORE_ALL_TURNS)} updates={said.get(BEFORE_ALL_TURNS)} />}
        {conversationId && <PullRequestNotices conversationId={conversationId} notices={noticed.get(BEFORE_ALL_TURNS)} />}
        <MemoryQuestions questions={asked.get(BEFORE_ALL_TURNS)} />
        {conversationId && <Plans conversationId={conversationId} plans={planned.get(BEFORE_ALL_TURNS)} />}
        {conversationId && (
          <Safeguards
            conversationId={conversationId}
            repairs={repaired.get(BEFORE_ALL_TURNS)}
            mitigations={mitigated.get(BEFORE_ALL_TURNS)}
            ownerAsks={owned.get(BEFORE_ALL_TURNS)}
          />
        )}
        {turns.map((turn) => (
          <Fragment key={turn.id}>
            <Message turn={turn} onOpenImage={setOpenImageId} />
            {conversationId && <HeldCalls conversationId={conversationId} heldCalls={held.get(turn.id)} />}
            {conversationId && <PackRefusals conversationId={conversationId} refusals={refused.get(turn.id)} />}
            {conversationId && <SecretEntries conversationId={conversationId} entries={handed.get(turn.id)} />}
            {conversationId && <Watches conversationId={conversationId} watches={watched.get(turn.id)} updates={said.get(turn.id)} />}
            {conversationId && <PullRequestNotices conversationId={conversationId} notices={noticed.get(turn.id)} />}
            <MemoryQuestions questions={asked.get(turn.id)} />
            {conversationId && <Plans conversationId={conversationId} plans={planned.get(turn.id)} />}
            {conversationId && (
              <Safeguards conversationId={conversationId} repairs={repaired.get(turn.id)} mitigations={mitigated.get(turn.id)} ownerAsks={owned.get(turn.id)} />
            )}
          </Fragment>
        ))}
        {live && <Message turn={live} live onOpenImage={setOpenImageId} />}
        {stream.busy && stream.text.length === 0 && <LoadingState label="Working" />}
        {waiting.map((message) => (
          <WaitingMessage key={message.id} body={message.body} attachments={message.attachments} onOpenImage={setOpenImageId} />
        ))}
        {conversationId && confirmations.length > 0 && !stream.busy && (
          <ConfirmCard conversationId={conversationId} confirmations={confirmations} />
        )}
        <div ref={foot} />
      </div>
      <ImageDialog image={openImage} onOpenChange={whenClosed(closeImage)} />
    </div>
  )
}

function sentAttachments(turns: ChatTurn[], waiting: AgentChatWaitingMessage[]): AgentChatAttachment[] {
  const asked = turns.flatMap((turn) => (turn.kind === TURN_KINDS.PERSON ? turn.attachments : []))
  return [ ...asked, ...waiting.flatMap((message) => message.attachments) ]
}
