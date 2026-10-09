import {
  IconBrain,
  IconBulb,
  IconChecklist,
  IconCircleCheck,
  IconDatabase,
  IconHandStop,
  IconMessage,
  IconMessageReply,
  IconPlayerPlay,
  IconPlugConnectedX,
  IconSend,
  IconSparkles,
  IconThumbUp,
  IconTool,
  type Icon,
} from "@tabler/icons-react"

import { OPERATOR_TRACE_KINDS } from "@/pages/operator/generated/constants"
import type { OperatorTraceSpan } from "@/types/serializers"

type Kind = OperatorTraceSpan["kind"]

export const KINDS: Record<Kind, { label: string; icon: Icon }> = {
  [OPERATOR_TRACE_KINDS.JOB]: { label: "Job", icon: IconPlayerPlay },
  [OPERATOR_TRACE_KINDS.FACTS]: { label: "Facts", icon: IconDatabase },
  [OPERATOR_TRACE_KINDS.MODEL]: { label: "Model call", icon: IconBrain },
  [OPERATOR_TRACE_KINDS.TOOL]: { label: "Tool call through the gateway", icon: IconTool },
  [OPERATOR_TRACE_KINDS.THEORY]: { label: "Theory", icon: IconBulb },
  [OPERATOR_TRACE_KINDS.CHECK]: { label: "Self check", icon: IconChecklist },
  [OPERATOR_TRACE_KINDS.ANSWER]: { label: "Answer", icon: IconCircleCheck },
  [OPERATOR_TRACE_KINDS.STOP]: { label: "Stop", icon: IconHandStop },
  [OPERATOR_TRACE_KINDS.POST]: { label: "Delivery", icon: IconSend },
  [OPERATOR_TRACE_KINDS.PLATFORM]: { label: "Failed platform call", icon: IconPlugConnectedX },
  [OPERATOR_TRACE_KINDS.VERDICT]: { label: "Verdict", icon: IconThumbUp },
  [OPERATOR_TRACE_KINDS.ASK]: { label: "Asked", icon: IconMessage },
  [OPERATOR_TRACE_KINDS.REPLY]: { label: "Reply", icon: IconMessageReply },
  [OPERATOR_TRACE_KINDS.RUN]: { label: "Run started", icon: IconSparkles },
}

export const MONO_KINDS: Kind[] = [OPERATOR_TRACE_KINDS.TOOL]
