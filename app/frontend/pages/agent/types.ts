import type { SharedProps } from "@/types"
import type { AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import type { AgentChat, AgentChatConfirmation, AgentChatIncident, AgentChatMessage } from "@/types/serializers"

// Every prop is always sent, so a partial visit can rely on the rest staying.
export interface AgentPageProps extends SharedProps {
  conversations: AgentChat[]
  archivedCount: number
  conversation: AgentChat | null
  incidents: AgentChatIncident[]
  messages: AgentChatMessage[]
  confirmations: AgentChatConfirmation[]
}

export type AgentStep = AgentChatMessage["tools"][number]

export type StepStatus = (typeof AGENT_STEP_STATUSES)[keyof typeof AGENT_STEP_STATUSES]

export type StreamEventType = (typeof AGENT_STREAM_EVENTS)[keyof typeof AGENT_STREAM_EVENTS]

export type ChatTurn =
  | { kind: "person"; id: string; body: string }
  | { kind: "agent"; id: string; steps: AgentStep[]; bodies: string[] }

export interface AgentStream {
  busy: boolean
  text: string
  steps: AgentStep[]
}
