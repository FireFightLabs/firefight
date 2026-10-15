import { router } from "@inertiajs/react"

import {
  AGENT_CHAT_ASKED_PROPS, AGENT_CHAT_DECIDED_PROPS, AGENT_CHAT_HEAD_PROPS, AGENT_CHAT_PROPS, AGENT_CHAT_THREAD_PROPS, CHAT_MESSAGE_ROLES,
  INVESTIGATION_QUERY_PARAM,
} from "@/lib/generated/constants"
import {
  agentChatAskPath, agentChatConfirmPath, agentChatMitigationExtendPath, agentChatMitigationKeepPath, agentChatMitigationUndoPath,
  agentChatPackRefusalAskPath, agentChatPath, agentChatPullRequestFixPath, agentChatSecretEntryFillPath, agentChatStopPath, agentChatsPath,
  agentChatWatchStopPath, investigationStopPath,
} from "@/lib/routes"
import type { AgentPageProps } from "@/pages/agent/types"
import type { AgentChat, AgentChatAttachment } from "@/types/serializers"

// The list loads by the page, so visits never ask for it again and rows change here instead.

type ChatChange = { title: string } | { pinned: boolean } | { archived: boolean }

// What the composer needs, which shows at once, and the conversation, which follows it in one request.
const CHAT_HEAD = [ ...AGENT_CHAT_HEAD_PROPS ]
const THREAD = [ ...AGENT_CHAT_THREAD_PROPS ]
const OPEN_CHAT = [ ...CHAT_HEAD, ...THREAD ]
// Messages load a page at a time and Inertia adds each page to what the page holds, so a visit that reads them again
// replaces them. It reads the whole stretch on screen, since each visit to the chat names its oldest message.
const MESSAGES = [ AGENT_CHAT_PROPS.MESSAGES ]
const READ_OPEN_CHAT = { only: OPEN_CHAT, reset: MESSAGES }
// A question and an answer to confirmations read back only what they change, never the cards around them or the list.
const READ_ASKED = { only: [ ...AGENT_CHAT_ASKED_PROPS ], reset: MESSAGES }
const READ_DECIDED = { only: [ ...AGENT_CHAT_DECIDED_PROPS ], reset: MESSAGES }
// A hovered chat is read ahead and kept this long, so opening it shows it at once.
export const CHAT_CACHE_FOR = "30s"
const CHARTS = [ AGENT_CHAT_PROPS.CHARTS ]
// A check's screenshots exist once it ran, and a send asked about after it shows the page it sends from.
const SCREENSHOTS = [ AGENT_CHAT_PROPS.SCREENSHOTS, AGENT_CHAT_PROPS.CONFIRMATIONS ]
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
// Continue starts a turn that carries the fix on under its step, so the chat and its steps are loaded with the card.
const CODE_PAUSES = [ AGENT_CHAT_PROPS.CODE_PAUSES, AGENT_CHAT_PROPS.MESSAGES, AGENT_CHAT_PROPS.CONVERSATION ]
// Rows a statement changed are counted and copied, a temporary change starts, is kept or undone, and an owner is asked
// or answers, often long after the answer, so the chat is told to look. A confirmation waiting on an owner moves too.
const SAFEGUARDS = [ AGENT_CHAT_PROPS.DATA_REPAIRS, AGENT_CHAT_PROPS.MITIGATIONS, AGENT_CHAT_PROPS.OWNER_ASKS, AGENT_CHAT_PROPS.CONFIRMATIONS ]
// Something contradicted a memory while Halon worked, so the chat asks which is right, and an answer settles the card.
export const MEMORY_QUESTIONS = [ AGENT_CHAT_PROPS.MEMORY_QUESTIONS ]
// A plan moves with every step Halon takes, and Retry or Undo start a turn, so the chat looks again.
const PLANS = [ AGENT_CHAT_PROPS.PLANS, AGENT_CHAT_PROPS.CONVERSATION ]
// A workflow made here is published, runs, ends or is cancelled long after the answer, so the chat looks again.
const WORKFLOWS = [ AGENT_CHAT_PROPS.WORKFLOWS ]
// Helpers start, take steps and report while the turn that handed them checks still works, and the charts they read
// arrive with them.
const HELPERS = [ AGENT_CHAT_PROPS.HELPERS, AGENT_CHAT_PROPS.CHARTS ]
// Something contradicted the handbook while Halon worked, or someone decided on its proposed edit.
export const HANDBOOK_PROPOSALS = [ AGENT_CHAT_PROPS.HANDBOOK_PROPOSALS ]
// Halon proposed a skill while it worked, or someone decided on it.
export const SKILL_PROPOSALS = [ AGENT_CHAT_PROPS.SKILL_PROPOSALS ]
// Which model the chat runs on, and whether that model reads images.
const CHAT_MODELS = [ AGENT_CHAT_PROPS.CHAT_MODELS, AGENT_CHAT_PROPS.ATTACHMENT_RULES ]
const RUNS = [ AGENT_CHAT_PROPS.INVESTIGATIONS, AGENT_CHAT_PROPS.OPEN_INVESTIGATION ]
const ARCHIVED_COUNT = [ AGENT_CHAT_PROPS.ARCHIVED_COUNT ]
const CONVERSATION = [ AGENT_CHAT_PROPS.CONVERSATION ]
// Without preserveState Inertia remounts the page and the list loses its scroll.
const KEEPS_PAGE = { preserveScroll: true, preserveState: true }
// Everything that stays on the chat shown (a change made from it, a card's action, a live reload) shows its result there,
// optimistically, by the card's own state or through the live connection. The progress bar would read as the page
// reloading, so only a visit that changes what is shown (opening a chat, a new chat, a run) shows it.
export const IN_PLACE = { ...KEEPS_PAGE, showProgress: false }

// Opening a chat shows its composer at once and a skeleton where the conversation goes, which loads next. The
// conversation is an ordinary visit, not a background one: Inertia drops a background response read ahead from another
// chat, and opening a third chat meanwhile should stop it.
const CHAT_HEAD_VISIT = { ...KEEPS_PAGE, only: CHAT_HEAD }
const THREAD_VISIT = { ...KEEPS_PAGE, only: THREAD, reset: MESSAGES }

// Spread onto a Link, so a chat stays a real link that opens in a new tab.
export function openChatVisit(chatId: string) {
  return { ...CHAT_HEAD_VISIT, onSuccess: () => openedChat(chatId) }
}

// Spread onto the link back to the list, which clears the open chat.
export const ALL_CHATS_VISIT = { ...KEEPS_PAGE, ...READ_OPEN_CHAT }

export function openChat(chatId: string) {
  router.visit(agentChatPath(chatId), openChatVisit(chatId))
}

// The link reads the composer's part ahead, and this the conversation, kept as long.
export function prefetchConversation(chatId: string) {
  router.prefetch(agentChatPath(chatId), THREAD_VISIT, { cacheFor: CHAT_CACHE_FOR })
}

// A chat read ahead may have moved on since, and nothing the live connection says before it connects is said again,
// so a chat opened from what was read ahead is read once more in the background.
function openedChat(chatId: string) {
  placeOpenChat()
  const path = agentChatPath(chatId)
  const readAhead = router.getCached(path, CHAT_HEAD_VISIT) !== null || router.getCached(path, THREAD_VISIT) !== null
  router.visit(path, { ...THREAD_VISIT, onSuccess: readAhead ? refreshOpenChat : undefined })
}

export function startNewChat() {
  router.visit(agentChatsPath(), ALL_CHATS_VISIT)
}

// The question and the working state show the moment it is sent, so the chat never sits still while the request is out.
// Sent while the agent works, it shows as waiting instead. The server's answer replaces both, and a refusal puts the page
// back.
// Files show on the message at once, an image from the copy the browser already holds, until the server's answer
// replaces it. A model picked before a new chat's first question goes with it.
// Only what a question changes is read back. A new chat, or one whose conversation has not arrived yet, reads it whole,
// since the question's visit takes the place of the one bringing the conversation.
export function ask(conversationId: string | null, threadReady: boolean, question: string, attachments: AgentChatAttachment[] = [],
  previews: Record<string, string> = {}, model: string | null = null) {
  const path = conversationId ? agentChatAskPath(conversationId) : agentChatsPath()
  const reads = conversationId && threadReady ? READ_ASKED : READ_OPEN_CHAT
  const shown = attachments.map((attachment) => ({ ...attachment, url: previews[attachment.id] ?? attachment.url }))
  const picked = model ? { model } : {}
  router
    .optimistic<AgentPageProps>((props) => askedNow(props, question, shown))
    .post(path, { question, attachment_ids: attachments.map((attachment) => attachment.id), ...picked }, {
      ...IN_PLACE, ...reads, onSuccess: placeOpenChat,
    })
}

// A new chat has no id until the server makes it, and an empty one opens no live connection. Messages are newest first.
// Asked before the chat's conversation arrived, the page shows the question alone until the server's answer brings the
// rest, and never what another chat left in the props.
function askedNow(props: AgentPageProps, question: string, attachments: AgentChatAttachment[]): Partial<AgentPageProps> {
  const loaded = props.conversation !== null && props.threadFor === props.conversation.id
  const waitingMessages = loaded ? props.waitingMessages ?? [] : []
  const messages = loaded ? props.messages ?? [] : []
  if (props.conversation?.busy) {
    const waiting = { id: `waiting-${waitingMessages.length}`, body: question, attachments }
    return { waitingMessages: [ ...waitingMessages, waiting ], ...(loaded ? {} : { messages, threadFor: props.conversation?.id }) }
  }

  const asked = {
    id: `asking-${messages.length}`, body: question, role: CHAT_MESSAGE_ROLES.USER, tools: [], sources: [], attachments,
    createdAt: new Date().toISOString(), model: null, saidAs: null,
  }
  const title = question || attachments.map((attachment) => attachment.name).join(", ")
  const now = new Date().toISOString()
  const conversation = props.conversation ?? {
    id: "", title, preview: question, archived: false, pinned: false, pinnedAt: null,
    lastActiveAt: now, busy: true, askedIn: null, askedInUrl: null, stopRequested: false, workingSince: now,
  }

  return {
    conversation: { ...conversation, busy: true, stopRequested: false, workingSince: conversation.workingSince ?? now },
    messages: [ asked, ...messages ], threadFor: conversation.id,
  }
}

// The picker moves the moment a model is picked and the server's toast confirms it. A refusal puts it back.
export function chooseChatModel(conversationId: string, model: string) {
  router
    .optimistic<AgentPageProps>((props) => (props.chatModels ? { chatModels: { ...props.chatModels, selected: model } } : {}))
    .patch(agentChatPath(conversationId), { model }, { ...IN_PLACE, only: CHAT_MODELS })
}

// The answer ends with Stopped once the worker stops, and the live connection brings that in.
// The chat stays as it is. Only whether it is stopping is read back, and the answer's end arrives on the live channel.
export function stopChat(conversationId: string) {
  router.post(agentChatStopPath(conversationId), {}, { ...IN_PLACE, only: CONVERSATION })
}

export function stopRun(investigationId: string) {
  router.post(investigationStopPath(investigationId), {}, { ...IN_PLACE, only: RUNS })
}

// expires is when a change customers feel is undone, as its confirmation offered it, or null for any other call.
export interface ConfirmationAnswer {
  toolCallId: string
  approved: boolean
  forChat: boolean
  expires: string | null
}

export function answerConfirmations(conversationId: string, answers: ConfirmationAnswer[]) {
  const decisions = answers.map((answer) => ({
    tool_call_id: answer.toolCallId, approved: answer.approved, for_chat: answer.forChat, expires: answer.expires,
  }))
  router.post(agentChatConfirmPath(conversationId), { decisions }, { ...IN_PLACE, ...READ_DECIDED })
}

// A run opens over the chat that started it, and only the run is loaded.
export function openRun(chatId: string, investigationId: string) {
  router.visit(agentChatPath(chatId, { [INVESTIGATION_QUERY_PARAM]: investigationId }), { ...KEEPS_PAGE, only: RUNS })
}

export function closeRun(chatId: string) {
  router.visit(agentChatPath(chatId), { ...KEEPS_PAGE, only: RUNS, replace: true })
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

// Continue and Stop on a paused code fix each post to their own path.
export function decideCodePause(path: string, callbacks: CardCallbacks) {
  router.post(path, {}, { ...IN_PLACE, only: CODE_PAUSES, reset: MESSAGES, ...callbacks })
}

export function fillSecretEntry(conversationId: string, entryId: string, value: string, callbacks: CardCallbacks) {
  router.post(agentChatSecretEntryFillPath(conversationId, entryId), { secret_value: value }, { ...IN_PLACE, only: SECRET_ENTRIES, ...callbacks })
}

// Schedule, Cancel, Retry and Undo on a plan each post to their own path.
export function sendPlanAction(path: string, callbacks: CardCallbacks) {
  router.post(path, {}, { ...IN_PLACE, only: PLANS, ...callbacks })
}

// Run now and Cancel on a workflow Halon made here post to one path, named by what was pressed.
export function pressWorkflow(path: string, callbacks: CardCallbacks) {
  router.post(path, {}, { ...IN_PLACE, only: WORKFLOWS, ...callbacks })
}

export function stopWatch(conversationId: string, watchId: string, callbacks: CardCallbacks) {
  router.post(agentChatWatchStopPath(conversationId, watchId), {}, { ...IN_PLACE, only: WATCHES, ...callbacks })
}

// Keep, One more hour and Undo now on a temporary change each post to their own path.
export function keepMitigation(conversationId: string, mitigationId: string, callbacks: CardCallbacks) {
  router.post(agentChatMitigationKeepPath(conversationId, mitigationId), {}, { ...IN_PLACE, only: SAFEGUARDS, ...callbacks })
}

export function extendMitigation(conversationId: string, mitigationId: string, callbacks: CardCallbacks) {
  router.post(agentChatMitigationExtendPath(conversationId, mitigationId), {}, { ...IN_PLACE, only: SAFEGUARDS, ...callbacks })
}

export function undoMitigation(conversationId: string, mitigationId: string, callbacks: CardCallbacks) {
  router.post(agentChatMitigationUndoPath(conversationId, mitigationId), {}, { ...IN_PLACE, only: SAFEGUARDS, ...callbacks })
}

// A coding agent's question and pause sit in a step's saved message, so answering one reloads the messages. Continue
// starts a turn and moves the pause's card in the thread too.
export const CODE_AGENT_RELOADS = CODE_PAUSES

function reloadInPlace(only: string[]) {
  router.reload({ ...IN_PLACE, only })
}

export function refreshRuns() {
  reloadInPlace(RUNS)
}

// A step that returned charts arrives while the answer is still being written, so only the charts are loaded.
export function refreshCharts() {
  reloadInPlace(CHARTS)
}

export function refreshScreenshots() {
  reloadInPlace(SCREENSHOTS)
}

export function refreshHeldCalls() {
  reloadInPlace(HELD_CALLS)
}

export function refreshPackRefusals() {
  reloadInPlace(PACK_REFUSALS)
}

export function refreshSecretEntries() {
  reloadInPlace(SECRET_ENTRIES)
}

export function refreshWatches() {
  reloadInPlace(WATCHES)
}

export function refreshPlans() {
  reloadInPlace(PLANS)
}

export function refreshWorkflows() {
  reloadInPlace(WORKFLOWS)
}

export function refreshPullRequestNotices() {
  reloadInPlace(PULL_REQUEST_NOTICES)
}

export function refreshSafeguards() {
  reloadInPlace(SAFEGUARDS)
}

export function refreshMemoryQuestions() {
  reloadInPlace(MEMORY_QUESTIONS)
}

export function refreshHelpers() {
  reloadInPlace(HELPERS)
}

export function refreshHandbookProposals() {
  reloadInPlace(HANDBOOK_PROPOSALS)
}

export function refreshSkillProposals() {
  reloadInPlace(SKILL_PROPOSALS)
}

export function refreshOpenChat() {
  router.reload({ ...IN_PLACE, ...READ_OPEN_CHAT, onSuccess: placeOpenChat })
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
  const reads = open ? { ...KEEPS_PAGE, ...READ_OPEN_CHAT, only: [ ...OPEN_CHAT, ...ARCHIVED_COUNT ] } : { ...IN_PLACE, only: ARCHIVED_COUNT }
  router
    .optimistic<AgentPageProps>((props) => ({
      conversations: props.conversations.filter((candidate) => candidate.id !== chat.id),
      archivedCount: props.archivedCount - (chat.archived ? 1 : 0),
    }))
    .delete(agentChatPath(chat.id), reads)
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
