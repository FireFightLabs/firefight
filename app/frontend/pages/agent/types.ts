import type { AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import type { AgentChatMessage } from "@/types/serializers"

// A step has one shape, live or saved, and the serializer owns it.
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
