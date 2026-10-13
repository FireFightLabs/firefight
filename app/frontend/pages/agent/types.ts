import type { SharedProps } from "@/types"
import type { AGENT_CHAT_THREAD_PROPS } from "@/lib/generated/constants"
import type {
  AgentChat, AgentChatAttachmentRules, AgentChatConfirmation, AgentChatDataRepair, AgentChatHeldCall, AgentChatHelper, AgentChatIncident,
  AgentChatCodePause, AgentChatMemoryQuestion, AgentChatMessage, AgentChatMitigation, AgentChatOwnerAsk, AgentChatPackRefusal, AgentChatPlan, AgentChatPullRequestNotice, AgentChatWorkflow, AgentChatSecretEntry, AgentChatWaitingMessage, AgentChatWatch, AgentChatWatchUpdate, ChatChart, ChatCompaction, ChatModelMenu, ChatModelSwitch, ChatScreenshot, ChatTheory, EnvironmentOption,
  HalonSkillProposal, HandbookProposal, IntegrationCard, InvestigationCard, InvestigationDetail,
} from "@/types/serializers"

export { TURN_KINDS } from "@/lib/agent-chat/types"
export type { AgentCard, AgentStep, AgentStream, AnswerSource, ChatTurn, RenderedTag, StepKind, StepStatus, StreamEventType, ToolActivity, TurnBody } from "@/lib/agent-chat/types"

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
  codePauses: AgentChatCodePause[]
  memoryQuestions: AgentChatMemoryQuestion[]
  plans: AgentChatPlan[]
  workflows: AgentChatWorkflow[]
  dataRepairs: AgentChatDataRepair[]
  mitigations: AgentChatMitigation[]
  ownerAsks: AgentChatOwnerAsk[]
  helpers: AgentChatHelper[]
  handbookProposals: HandbookProposal[]
  skillProposals: HalonSkillProposal[]
  theories: ChatTheory[]
}

// The dialogs a secret entry opens, to type a value or to reveal one.
export interface SecretDialogProps {
  conversationId: string
  entry: AgentChatSecretEntry
  open: boolean
  onClose: () => void
}
