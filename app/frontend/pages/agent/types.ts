import type { SharedProps } from "@/types"
import type { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import type { AgentChat, AgentChatConfirmation, AgentChatIncident, AgentChatMessage, EnvironmentOption, IntegrationCard } from "@/types/serializers"

// Every prop is always sent, so a partial visit can rely on the rest staying.
export interface AgentPageProps extends SharedProps {
  conversations: AgentChat[]
  archivedCount: number
  conversation: AgentChat | null
  incidents: AgentChatIncident[]
  messages: AgentChatMessage[]
  confirmations: AgentChatConfirmation[]
  integrationCards: IntegrationCard[]
  environments: EnvironmentOption[]
}

export type AgentStep = AgentChatMessage["tools"][number]

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

export type ChatTurn =
  | { kind: typeof TURN_KINDS.PERSON; id: string; body: string }
  | { kind: typeof TURN_KINDS.AGENT; id: string; steps: AgentStep[]; bodies: TurnBody[] }

export interface AgentStream {
  // The agent is working on an answer and has not said it is done.
  busy: boolean
  // The server owes an answer, so what is saved after the last question is the turn in progress.
  owed: boolean
  text: string
  steps: AgentStep[]
}
