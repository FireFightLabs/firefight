import { router } from "@inertiajs/react"

import { AGENT_CHAT_PROPS } from "@/lib/generated/constants"
import { agentChatAskPath, agentChatPath, agentChatsPath } from "@/lib/routes"
import type { AgentChat } from "@/types/serializers"

// Every change to the chat list happens in place. The list loads by the page, so asking the server for
// it again would drop every page past the first and the reader's place in it. Visits ask only for what
// changed, and rows are updated here, the way the server would order them.

interface ChatPageProps {
  conversations: AgentChat[]
  archivedCount: number
  conversation: AgentChat | null
}

// What a visit to another chat, or a finished answer, changes. The list is left alone.
const OPEN_CHAT = [ AGENT_CHAT_PROPS.CONVERSATION, AGENT_CHAT_PROPS.MESSAGES ]
// A tidy action changes one row, which the page updates itself, and possibly how many are archived.
const ARCHIVED_COUNT = [ AGENT_CHAT_PROPS.ARCHIVED_COUNT ]
// Inertia remounts the page on a visit unless told otherwise, which would reset the list's scroll.
const IN_PLACE = { preserveScroll: true, preserveState: true }

// For a link to a chat, which stays a real link so it opens in a new tab and reads as one.
export const OPEN_CHAT_VISIT = { ...IN_PLACE, only: OPEN_CHAT, onSuccess: placeOpenChat }

export function openChat(chatId: string) {
  router.visit(agentChatPath(chatId), OPEN_CHAT_VISIT)
}

export function startNewChat() {
  router.visit(agentChatsPath(), { ...IN_PLACE, only: OPEN_CHAT })
}

// With no chat open, the first question is what creates one.
export function ask(conversationId: string | null, question: string) {
  const path = conversationId ? agentChatAskPath(conversationId) : agentChatsPath()
  router.post(path, { question }, { ...IN_PLACE, only: OPEN_CHAT, onSuccess: placeOpenChat })
}

export function refreshOpenChat() {
  router.reload({ only: OPEN_CHAT, onSuccess: placeOpenChat })
}

export function renameChat(chat: AgentChat, title: string) {
  changeChat(chat, { title }, { title })
}

export function setChatPinned(chat: AgentChat, pinned: boolean) {
  changeChat(chat, { pinned, pinnedAt: pinned ? new Date().toISOString() : null }, { pinned })
}

export function setChatArchived(chat: AgentChat, archived: boolean) {
  changeChat(chat, { archived }, { archived })
}

// The open chat leaves nothing to show once it is gone, so that one clears the page too.
export function deleteChat(chat: AgentChat, open: boolean) {
  router
    .optimistic<ChatPageProps>((props) => ({
      conversations: props.conversations.filter((candidate) => candidate.id !== chat.id),
      archivedCount: props.archivedCount - (chat.archived ? 1 : 0),
    }))
    .delete(agentChatPath(chat.id), { ...IN_PLACE, only: open ? [ ...OPEN_CHAT, ...ARCHIVED_COUNT ] : ARCHIVED_COUNT })
}

function changeChat(chat: AgentChat, changes: Partial<AgentChat>, params: Record<string, string | boolean>) {
  const archivedShift = changes.archived === undefined ? 0 : Number(changes.archived) - Number(chat.archived)

  router
    .optimistic<ChatPageProps>((props) => ({
      conversations: props.conversations.map((candidate) => (candidate.id === chat.id ? { ...candidate, ...changes } : candidate)),
      archivedCount: props.archivedCount + archivedShift,
    }))
    .patch(agentChatPath(chat.id), params, { ...IN_PLACE, only: ARCHIVED_COUNT })
}

// The open chat as the server now has it, put into the list in place of its old row, or added if new.
function placeOpenChat() {
  router.replaceProp<ChatPageProps>(AGENT_CHAT_PROPS.CONVERSATIONS, (_current: unknown, props: ChatPageProps) => {
    const open = props.conversation
    if (!open) {
      return props.conversations
    }

    return [ open, ...props.conversations.filter((candidate) => candidate.id !== open.id) ]
  })
}
