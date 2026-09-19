import { router } from "@inertiajs/react"

import { AGENT_CHAT_PROPS } from "@/lib/generated/constants"
import { agentChatAskPath, agentChatPath, agentChatsPath } from "@/lib/routes"
import type { AgentPageProps } from "@/pages/agent/types"
import type { AgentChat } from "@/types/serializers"

// The list loads by the page, so visits never ask for it again and rows change here instead.

type ChatChange = { title: string } | { pinned: boolean } | { archived: boolean }

const OPEN_CHAT = [ AGENT_CHAT_PROPS.CONVERSATION, AGENT_CHAT_PROPS.MESSAGES ]
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

export function ask(conversationId: string | null, question: string) {
  const path = conversationId ? agentChatAskPath(conversationId) : agentChatsPath()
  router.post(path, { question }, { ...IN_PLACE, only: OPEN_CHAT, onSuccess: placeOpenChat })
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
