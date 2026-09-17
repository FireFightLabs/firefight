import type { AgentChat } from "@/types/serializers"

export interface ChatGroup {
  label: string
  chats: AgentChat[]
}

const DAY_MS = 24 * 60 * 60 * 1000

// Chats read as a diary, so the list says which day it is rather than repeating a date on each row.
function labelFor(when: Date, now: Date): string {
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
  const day = new Date(when.getFullYear(), when.getMonth(), when.getDate()).getTime()
  const daysAgo = Math.round((startOfToday - day) / DAY_MS)

  if (daysAgo <= 0) {
    return "Today"
  }
  if (daysAgo === 1) {
    return "Yesterday"
  }
  if (daysAgo < 7) {
    return when.toLocaleDateString(undefined, { weekday: "long" })
  }

  return when.toLocaleDateString(undefined, { month: "short", day: "numeric" })
}

export function groupedByDay(chats: AgentChat[], now: Date = new Date()): ChatGroup[] {
  const groups: ChatGroup[] = []

  chats.forEach((chat) => {
    const label = chat.pinned ? "Pinned" : labelFor(new Date(chat.updatedAt), now)
    const existing = groups.find((group) => group.label === label)
    if (existing) {
      existing.chats.push(chat)
      return
    }

    groups.push({ label, chats: [ chat ] })
  })

  return groups
}
