import type { ComponentProps } from "react"

import type { SharedProps } from "@/types"
import type { AGENT_CHAT_THREAD_PROPS, AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import type {
  AgentChat, AgentChatAttachment, AgentChatAttachmentRules, AgentChatConfirmation, AgentChatDataRepair, AgentChatHeldCall, AgentChatHelper, AgentChatIncident,
  AgentChatMemoryQuestion, AgentChatMessage, AgentChatMitigation, AgentChatOwnerAsk, AgentChatPackRefusal, AgentChatPlan, AgentChatPullRequestNotice, AgentChatSecretEntry, AgentChatWaitingMessage, AgentChatWatch, AgentChatWatchUpdate, ChatChart, ChatCompaction, ChatModelMenu, ChatModelSwitch, ChatScreenshot, ChatTheory, EnvironmentOption,
  HandbookProposal, IntegrationCard, InvestigationCard, InvestigationDetail,
} from "@/types/serializers"

// Setup's Meet Halon step, sent only while an admin is on it.
export interface SetupGuide {
  question: string
  answered: boolean
  setupPath: string
}

// Every prop is always sent, so a partial visit can rely on the rest staying. An open chat's conversation (the
// AGENT_CHAT_THREAD_PROPS) is a deferred group, absent until it arrives just after the page shows.
export interface AgentPageProps extends SharedProps, Partial<ThreadProps> {
  conversations: AgentChat[]
  archivedCount: number
  conversation: AgentChat | null
  incidents: AgentChatIncident[]
  integrationCards: IntegrationCard[]
  environments: EnvironmentOption[]
  openInvestigation: InvestigationDetail | null
  attachmentRules: AgentChatAttachmentRules
  setupGuide: SetupGuide | null
  chatModels: ChatModelMenu | null
}

// The open chat's conversation. Messages come newest first, a page at a time, and the rest is read for the stretch of
// the chat its messages cover.
export interface ThreadProps extends Record<(typeof AGENT_CHAT_THREAD_PROPS)[number], unknown> {
  // The chat these were read for, so a page switching chats never shows the last one's.
  threadFor: string | null
  messages: AgentChatMessage[]
  confirmations: AgentChatConfirmation[]
  waitingMessages: AgentChatWaitingMessage[]
  investigations: InvestigationCard[]
  charts: ChatChart[]
  screenshots: ChatScreenshot[]
  compactions: ChatCompaction[]
  modelSwitches: ChatModelSwitch[]
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
  helpers: AgentChatHelper[]
  handbookProposals: HandbookProposal[]
  theories: ChatTheory[]
}

// What a long tool last said about how far it got, sent live while it runs and never saved, so only a step the socket
// reported carries one.
export interface ToolActivity {
  message: string | null
  value: number | null
  total: number | null
}

export type AgentStep = AgentChatMessage["tools"][number] & { activity?: ToolActivity | null }

export type AgentCard = NonNullable<AgentStep["card"]>

export type StepStatus = (typeof AGENT_STEP_STATUSES)[keyof typeof AGENT_STEP_STATUSES]

export type StepKind = (typeof AGENT_STEP_KINDS)[keyof typeof AGENT_STEP_KINDS]

export type StreamEventType = (typeof AGENT_STREAM_EVENTS)[keyof typeof AGENT_STREAM_EVENTS]

// Who a drawn turn belongs to. Page only, since the server saves messages by role and the page groups them.
export const TURN_KINDS = { PERSON: "person", AGENT: "agent" } as const

// One piece of an answer, keyed by the message it was saved as, or by the live stream.
export interface TurnBody {
  id: string
  text: string
}

// Something Halon read to give an answer, with the page it came from when its result gave one.
export type AnswerSource = AgentChatMessage["sources"][number]

export type ChatTurn =
  | { kind: typeof TURN_KINDS.PERSON; id: string; body: string; attachments: AgentChatAttachment[] }
  | { kind: typeof TURN_KINDS.AGENT; id: string; steps: AgentStep[]; bodies: TurnBody[]; models: string[]; sources: AnswerSource[] }

export interface AgentStream {
  // The agent is working on an answer and has not said it is done.
  busy: boolean
  // The server owes an answer, so what is saved after the last question is the turn in progress.
  owed: boolean
  text: string
  steps: AgentStep[]
}

// A tag react-markdown renders through one of our components, with the syntax tree node it passes along.
export type RenderedTag<Tag extends "a" | "pre" | "table"> = ComponentProps<Tag> & { node?: unknown }

// The dialogs a secret entry opens, to type a value or to reveal one.
export interface SecretDialogProps {
  conversationId: string
  entry: AgentChatSecretEntry
  open: boolean
  onClose: () => void
}
