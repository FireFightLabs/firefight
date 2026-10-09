import { router } from "@inertiajs/react"

import { AGENT_CHAT_PROPS, CHAT_MESSAGE_ROLES, INVESTIGATION_QUERY_PARAM } from "@/lib/generated/constants"
import {
  agentChatAskPath, agentChatConfirmPath, agentChatPackRefusalAskPath, agentChatPath, agentChatPullRequestFixPath, agentChatSecretEntryFillPath,
  agentChatStopPath, agentChatsPath, agentChatWatchStopPath, investigationStopPath,
} from "@/lib/routes"
import type { AgentPageProps } from "@/pages/agent/types"
import type { AgentChat, AgentChatAttachment } from "@/types/serializers"

// The list loads by the page, so visits never ask for it again and rows change here instead.

type ChatChange = { title: string } | { pinned: boolean } | { archived: boolean }

const OPEN_CHAT = [
  AGENT_CHAT_PROPS.CONVERSATION, AGENT_CHAT_PROPS.MESSAGES, AGENT_CHAT_PROPS.CONFIRMATIONS,
  AGENT_CHAT_PROPS.INVESTIGATIONS, AGENT_CHAT_PROPS.OPEN_INVESTIGATION, AGENT_CHAT_PROPS.CHARTS,
  AGENT_CHAT_PROPS.WAITING_MESSAGES, AGENT_CHAT_PROPS.ATTACHMENT_RULES, AGENT_CHAT_PROPS.COMPACTIONS, AGENT_CHAT_PROPS.HELD_CALLS,
  AGENT_CHAT_PROPS.PACK_REFUSALS, AGENT_CHAT_PROPS.SECRET_ENTRIES, AGENT_CHAT_PROPS.SETUP_GUIDE, AGENT_CHAT_PROPS.WATCHES, AGENT_CHAT_PROPS.WATCH_UPDATES,
  AGENT_CHAT_PROPS.PULL_REQUEST_NOTICES,
]
const CHARTS = [ AGENT_CHAT_PROPS.CHARTS ]
// A held call moves on when someone approves it, Halon checks it, it runs or it expires, so the chat is told to look.
const HELD_CALLS = [ AGENT_CHAT_PROPS.HELD_CALLS, AGENT_CHAT_PROPS.CONVERSATION ]
// A refusal appears after Halon was refused a change, and says when the admins were asked once someone asks.
const PACK_REFUSALS = [ AGENT_CHAT_PROPS.PACK_REFUSALS ]
// A secret appears when a tool call hands one to the person, and says when it was set.
const SECRET_ENTRIES = [ AGENT_CHAT_PROPS.SECRET_ENTRIES ]
// A watch starts, says a line or ends on its own, long after the answer, so the chat is told to look.
const WATCHES = [ AGENT_CHAT_PROPS.WATCHES, AGENT_CHAT_PROPS.WATCH_UPDATES ]
// A pull request Halon opened needs attention long after the answer, or Fix it was pressed, so the chat is told to look.
const PULL_REQUEST_NOTICES = [ AGENT_CHAT_PROPS.PULL_REQUEST_NOTICES ]
const RUNS = [ AGENT_CHAT_PROPS.INVESTIGATIONS, AGENT_CHAT_PROPS.OPEN_INVESTIGATION ]
const ARCHIVED_COUNT = [ AGENT_CHAT_PROPS.ARCHIVED_COUNT ]
// Without preserveState Inertia remounts the page and the list loses its scroll.
const IN_PLACE = { preserveScroll: true, preserveState: true }

// Spread onto a Link, so a chat stays a real link that opens in a new tab.
export const OPEN_CHAT_VISIT = { ...IN_PLACE, only: OPEN_CHAT, onSuccess: placeOpenChat }

export function openChat(chatId: string) {
  router.visit(agentChatPath(chatId), OPEN_CHAT_VISIT)
}

export function startNewChat() {
  router.visit(agentChatsPath(), { ...IN_PLACE, only: OPEN_CHAT })
}

// The question and the working state show the moment it is sent, so the chat never sits still while the request is out.
// Sent while the agent works, it shows as waiting instead. The server's answer replaces both, and a refusal puts the page
// back.
// Files show on the message at once, an image from the copy the browser already holds, until the server's answer
// replaces it.
export function ask(conversationId: string | null, question: string, attachments: AgentChatAttachment[] = [], previews: Record<string, string> = {}) {
  const path = conversationId ? agentChatAskPath(conversationId) : agentChatsPath()
  const shown = attachments.map((attachment) => ({ ...attachment, url: previews[attachment.id] ?? attachment.url }))
  router
    .optimistic<AgentPageProps>((props) => askedNow(props, question, shown))
    .post(path, { question, attachment_ids: attachments.map((attachment) => attachment.id) }, {
      ...IN_PLACE, only: OPEN_CHAT, onSuccess: placeOpenChat,
    })
}

// A new chat has no id until the server makes it, and an empty one opens no live connection.
function askedNow(props: AgentPageProps, question: string, attachments: AgentChatAttachment[]): Partial<AgentPageProps> {
  if (props.conversation?.busy) {
    const waiting = { id: `waiting-${props.waitingMessages.length}`, body: question, attachments }
    return { waitingMessages: [ ...props.waitingMessages, waiting ] }
  }

  const asked = {
    id: `asking-${props.messages.length}`, body: question, role: CHAT_MESSAGE_ROLES.USER, tools: [], attachments,
    createdAt: new Date().toISOString(),
  }
  const title = question || attachments.map((attachment) => attachment.name).join(", ")
  const conversation = props.conversation ?? {
    id: "", title, preview: question, archived: false, pinned: false, pinnedAt: null,
    lastActiveAt: new Date().toISOString(), busy: true,
  }

  return { conversation: { ...conversation, busy: true }, messages: [ ...props.messages, asked ] }
}

// The answer ends with Stopped once the worker stops, and the live connection brings that in.
export function stopChat(conversationId: string) {
  router.post(agentChatStopPath(conversationId), {}, { ...IN_PLACE, only: OPEN_CHAT })
}

export function stopRun(investigationId: string) {
  router.post(investigationStopPath(investigationId), {}, { ...IN_PLACE, only: RUNS })
}

export interface ConfirmationAnswer {
  toolCallId: string
  approved: boolean
  forChat: boolean
}

export function answerConfirmations(conversationId: string, answers: ConfirmationAnswer[]) {
  const decisions = answers.map((answer) => ({ tool_call_id: answer.toolCallId, approved: answer.approved, for_chat: answer.forChat }))
  router.post(agentChatConfirmPath(conversationId), { decisions }, { ...IN_PLACE, only: OPEN_CHAT })
}

// A run opens over the chat that started it, and only the run is loaded.
export function openRun(chatId: string, investigationId: string) {
  router.visit(agentChatPath(chatId, { [INVESTIGATION_QUERY_PARAM]: investigationId }), { ...IN_PLACE, only: RUNS })
}

export function closeRun(chatId: string) {
  router.visit(agentChatPath(chatId), { ...IN_PLACE, only: RUNS, replace: true })
}

// A run answers after the turn that started it, so its card is told to look again whenever it moves.
// A card's action reloads only the card's own props, so the redirect after it never asks for the list again.
interface CardCallbacks {
  onSuccess?: () => void
  onFinish: () => void
}

// Run, Dismiss and Ask again on a held call each post to their own path.
export function sendHeldCallAction(path: string, callbacks: CardCallbacks) {
  router.post(path, {}, { ...IN_PLACE, only: HELD_CALLS, ...callbacks })
}

export function askAdminForPack(conversationId: string, refusalId: string, callbacks: CardCallbacks) {
  router.post(agentChatPackRefusalAskPath(conversationId, refusalId), {}, { ...IN_PLACE, only: PACK_REFUSALS, ...callbacks })
}

export function fixPullRequest(conversationId: string, noticeId: string, callbacks: CardCallbacks) {
  router.post(agentChatPullRequestFixPath(conversationId, noticeId), {}, { ...IN_PLACE, only: PULL_REQUEST_NOTICES, ...callbacks })
}

export function fillSecretEntry(conversationId: string, entryId: string, value: string, callbacks: CardCallbacks) {
  router.post(agentChatSecretEntryFillPath(conversationId, entryId), { secret_value: value }, { ...IN_PLACE, only: SECRET_ENTRIES, ...callbacks })
}

export function stopWatch(conversationId: string, watchId: string, callbacks: CardCallbacks) {
  router.post(agentChatWatchStopPath(conversationId, watchId), {}, { ...IN_PLACE, only: WATCHES, ...callbacks })
}

// A coding agent's question and pause sit in a step's saved message, so answering one reloads the messages.
export const CODE_AGENT_RELOADS = [ AGENT_CHAT_PROPS.MESSAGES ]

export function refreshRuns() {
  router.reload({ only: RUNS })
}

// A step that returned charts arrives while the answer is still being written, so only the charts are loaded.
export function refreshCharts() {
  router.reload({ only: CHARTS })
}

export function refreshHeldCalls() {
  router.reload({ only: HELD_CALLS })
}

export function refreshPackRefusals() {
  router.reload({ only: PACK_REFUSALS })
}

export function refreshSecretEntries() {
  router.reload({ only: SECRET_ENTRIES })
}

export function refreshWatches() {
  router.reload({ only: WATCHES })
}

export function refreshPullRequestNotices() {
  router.reload({ only: PULL_REQUEST_NOTICES })
}

export function refreshOpenChat() {
  router.reload({ only: OPEN_CHAT, onSuccess: placeOpenChat })
}

export function renameChat(chat: AgentChat, title: string) {
  changeChat(chat, { title })
}

// pinnedAt is what the pinned section sorts on.
export function setChatPinned(chat: AgentChat, pinned: boolean) {
  changeChat(chat, { pinned }, { pinnedAt: pinned ? new Date().toISOString() : null })
}

export function setChatArchived(chat: AgentChat, archived: boolean) {
  changeChat(chat, { archived })
}

// Deleting the open chat clears the page too.
export function deleteChat(chat: AgentChat, open: boolean) {
  router
    .optimistic<AgentPageProps>((props) => ({
      conversations: props.conversations.filter((candidate) => candidate.id !== chat.id),
      archivedCount: props.archivedCount - (chat.archived ? 1 : 0),
    }))
    .delete(agentChatPath(chat.id), { ...IN_PLACE, only: open ? [ ...OPEN_CHAT, ...ARCHIVED_COUNT ] : ARCHIVED_COUNT })
}

function changeChat(chat: AgentChat, change: ChatChange, alsoOnRow: Partial<AgentChat> = {}) {
  const row = { ...chat, ...change, ...alsoOnRow }
  const archivedShift = Number(row.archived) - Number(chat.archived)

  router
    .optimistic<AgentPageProps>((props) => ({
      conversations: props.conversations.map((candidate) => (candidate.id === chat.id ? row : candidate)),
      archivedCount: props.archivedCount + archivedShift,
    }))
    .patch(agentChatPath(chat.id), change, { ...IN_PLACE, only: ARCHIVED_COUNT })
}

function placeOpenChat() {
  router.replaceProp<AgentPageProps>(AGENT_CHAT_PROPS.CONVERSATIONS, (_current: unknown, props: AgentPageProps) => {
    const open = props.conversation
    if (!open) {
      return props.conversations
    }

    return [ open, ...props.conversations.filter((candidate) => candidate.id !== open.id) ]
  })
}
