import { type ChatStreamHandlers, useChatStream } from "@/hooks/use-chat-stream"
import type { StreamEvent } from "@/lib/agent-chat/stream-order"
import { AGENT_CARD_KINDS, AGENT_STREAM_EVENTS } from "@/lib/generated/constants"
import {
  refreshCharts, refreshHandbookProposals, refreshSkillProposals, refreshScreenshots, refreshHeldCalls, refreshHelpers, refreshOpenChat, refreshPackRefusals, refreshPlans, refreshWorkflows,
  refreshPullRequestNotices, refreshRuns,
  refreshSafeguards, refreshSecretEntries,
  refreshWatches,
} from "@/pages/agent/lib/chat-updates"
import type { AgentStream } from "@/pages/agent/types"

// Each event that only says part of the open chat changed, with what reloads it.
const NOTICES: Partial<Record<string, () => void>> = {
  [AGENT_STREAM_EVENTS.INVESTIGATION]: refreshRuns,
  [AGENT_STREAM_EVENTS.HELD_CALL]: refreshHeldCalls,
  [AGENT_STREAM_EVENTS.PACK_REFUSAL]: refreshPackRefusals,
  [AGENT_STREAM_EVENTS.SECRET_ENTRY]: refreshSecretEntries,
  [AGENT_STREAM_EVENTS.WATCH]: refreshWatches,
  [AGENT_STREAM_EVENTS.CODE_FIX]: refreshOpenChat,
  [AGENT_STREAM_EVENTS.PULL_REQUEST]: refreshPullRequestNotices,
  [AGENT_STREAM_EVENTS.PLAN]: refreshPlans,
  [AGENT_STREAM_EVENTS.WORKFLOW]: refreshWorkflows,
  [AGENT_STREAM_EVENTS.SAFEGUARD]: refreshSafeguards,
  [AGENT_STREAM_EVENTS.HELPERS]: refreshHelpers,
  [AGENT_STREAM_EVENTS.HANDBOOK]: refreshHandbookProposals,
  [AGENT_STREAM_EVENTS.SKILL]: refreshSkillProposals,
}

function onNotice(event: StreamEvent): boolean {
  const refresh = NOTICES[event.type]
  if (!refresh) {
    return false
  }
  refresh()
  return true
}

// A step that brought a chart or screenshots reloads them, so its card has them when it draws.
function onStreamed(event: StreamEvent) {
  if (event.type !== AGENT_STREAM_EVENTS.STEP) {
    return
  }
  if (event.card?.kind === AGENT_CARD_KINDS.CHART) {
    refreshCharts()
  }
  if (event.card?.kind === AGENT_CARD_KINDS.SCREENSHOTS) {
    refreshScreenshots()
  }
}

const HANDLERS: ChatStreamHandlers = { reloadChat: refreshOpenChat, onNotice, onStreamed }

export function useAgentStream(conversationId: string | null, owed: boolean): AgentStream {
  return useChatStream(conversationId, owed, HANDLERS)
}
