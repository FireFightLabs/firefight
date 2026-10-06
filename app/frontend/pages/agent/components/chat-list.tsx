import { InfiniteScroll } from "@inertiajs/react"
import { IconChevronRight, IconLayoutSidebarLeftCollapse, IconLoader2, IconMessages, IconPencilPlus, IconSearch } from "@tabler/icons-react"
import { useCallback, useState } from "react"

import { AGENT_CHAT_PROPS } from "@/lib/generated/constants"
import { ChatListSection } from "@/pages/agent/components/chat-list-section"
import { ChatSearch } from "@/pages/agent/components/chat-search"
import { ListButton } from "@/pages/agent/components/list-button"
import { useSearchShortcut } from "@/hooks/use-search-shortcut"
import type { AgentChat } from "@/types/serializers"

const SCROLL_BUFFER_PX = 200

interface ChatListProps {
  chats: AgentChat[]
  archivedCount: number
  currentId: string | null
  className: string
  onNewChat: () => void
  onCollapse: () => void
}

// The archived count comes from the server, since later pages may not have loaded yet.
export function ChatList({ chats: loaded, archivedCount, currentId, className, onNewChat, onCollapse }: ChatListProps) {
  const chats = uniqueById(loaded)
  const pinned = chats.filter((chat) => chat.pinned && !chat.archived).sort(byNewest("pinnedAt"))
  const recent = chats.filter((chat) => !chat.pinned && !chat.archived).sort(byNewest("lastActiveAt"))
  const archived = chats.filter((chat) => chat.archived).sort(byNewest("lastActiveAt"))
  const currentIsArchived = archived.some((chat) => chat.id === currentId)

  const [ searching, setSearching ] = useState(false)
  const [ showArchived, setShowArchived ] = useState(currentIsArchived)
  const [ unfoldedFor, setUnfoldedFor ] = useState(currentId)

  // Opening an archived chat unfolds its section, and the person can still fold it.
  if (currentId !== unfoldedFor) {
    setUnfoldedFor(currentId)
    if (currentIsArchived) {
      setShowArchived(true)
    }
  }
  const openSearch = useCallback(() => setSearching(true), [])
  useSearchShortcut(openSearch)

  function toggleArchived() {
    setShowArchived((shown) => !shown)
  }

  return (
    <aside className={`agent-chat-list min-h-0 flex-col gap-4 overflow-hidden border-r border-line px-2 py-3 ${className}`}>
      <div className="flex items-center justify-between px-2">
        <h2 className="text-[14px] font-semibold text-ink">Chats</h2>
        <div className="flex items-center gap-0.5">
          <ListButton icon={IconSearch} label="Search chats" onClick={openSearch} />
          <ListButton icon={IconPencilPlus} label="New chat" onClick={onNewChat} />
          <ListButton icon={IconLayoutSidebarLeftCollapse} label="Hide chats" onClick={onCollapse} className="hidden md:flex" />
        </div>
      </div>

      <nav className="-mr-2 min-h-0 flex-1 overflow-y-auto pr-2 [scrollbar-color:var(--line-strong)_transparent] [scrollbar-width:thin]">
        <InfiniteScroll
          data={AGENT_CHAT_PROPS.CONVERSATIONS}
          preserveUrl
          onlyNext
          buffer={SCROLL_BUFFER_PX}
          className="flex flex-col gap-4"
          loading={
            <p className="flex items-center gap-1.5 px-2.5 text-[12px] text-ink-3">
              <IconLoader2 className="size-3.5 animate-spin" />
              Loading more chats
            </p>
          }
        >
          {chats.length === 0 && (
            <p className="flex items-center gap-2 px-2.5 py-1 text-[12.5px] text-ink-3">
              <IconMessages className="size-4 shrink-0" />
              No chats yet.
            </p>
          )}
          <ChatListSection label="Pinned" chats={pinned} currentId={currentId} />
          {byDay(recent).map((day) => (
            <ChatListSection key={day.label} label={day.label} chats={day.chats} currentId={currentId} />
          ))}

          {archivedCount > 0 && (
            <div className="flex flex-col gap-0.5">
              <button
                type="button"
                onClick={toggleArchived}
                aria-expanded={showArchived}
                className="flex items-center gap-1 rounded-control px-2.5 pb-1 text-[12px] text-ink-3 transition-colors duration-150 hover:text-ink-2"
              >
                <IconChevronRight className={`size-3.5 transition-transform duration-150 ${showArchived ? "rotate-90" : ""}`} />
                Archived ({archivedCount})
              </button>
              {showArchived && <ChatListSection chats={archived} currentId={currentId} />}
            </div>
          )}
        </InfiniteScroll>
      </nav>

      <ChatSearch chats={chats} open={searching} onOpenChange={setSearching} />
    </aside>
  )
}

// A chat that moves up while pages load can arrive twice, and the first copy is the newer one.
function uniqueById(chats: AgentChat[]): AgentChat[] {
  const seen = new Set<string>()

  return chats.filter((chat) => {
    if (seen.has(chat.id)) {
      return false
    }
    seen.add(chat.id)
    return true
  })
}

// Same order as the server, so a changed row lands where a reload would put it.
function byNewest(key: "pinnedAt" | "lastActiveAt") {
  return (first: AgentChat, second: AgentChat) => (second[key] ?? "").localeCompare(first[key] ?? "")
}

const DAY_MS = 24 * 60 * 60 * 1000

interface Day {
  label: string
  chats: AgentChat[]
}

// Recent chats under when they were last used, the way a person remembers them. The chats arrive newest first.
function byDay(chats: AgentChat[]): Day[] {
  const midnight = new Date()
  midnight.setHours(0, 0, 0, 0)
  const today = midnight.getTime()

  return chats.reduce<Day[]>((days, chat) => {
    const label = dayLabel(new Date(chat.lastActiveAt).getTime(), today)
    const open = days[days.length - 1]
    if (open && open.label === label) {
      open.chats.push(chat)
      return days
    }

    return [ ...days, { label, chats: [ chat ] } ]
  }, [])
}

function dayLabel(lastActive: number, today: number) {
  if (lastActive >= today) {
    return "Today"
  }
  if (lastActive >= today - DAY_MS) {
    return "Yesterday"
  }
  if (lastActive >= today - 7 * DAY_MS) {
    return "Previous 7 days"
  }
  if (lastActive >= today - 30 * DAY_MS) {
    return "Previous 30 days"
  }

  return "Older"
}
