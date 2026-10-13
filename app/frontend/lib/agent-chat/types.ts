import type { ComponentProps } from "react"

import type { AGENT_STEP_KINDS, AGENT_STEP_STATUSES, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import type { AgentChatAttachment, AgentChatMessage } from "@/types/serializers"

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
