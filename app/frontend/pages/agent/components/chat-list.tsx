import { router } from "@inertiajs/react"
import { IconMessageCircle, IconPencilPlus, IconSearch } from "@tabler/icons-react"
import { useMemo, useRef, useState } from "react"

import { agentChatsPath } from "@/lib/routes"
import { ChatRow } from "@/pages/agent/components/chat-row"
import { useSearchShortcut } from "@/pages/agent/hooks/use-search-shortcut"
import { groupedByDay, type ChatGroup } from "@/pages/agent/lib/group-chats"
import type { AgentChat } from "@/types/serializers"

interface ChatListProps {
  chats: AgentChat[]
  currentId?: string
  className: string
}

const FILTER_ALL = "All"
const FILTER_PINNED = "Pinned"
const FILTER_ARCHIVED = "Archived"
const FILTERS = [ FILTER_ALL, FILTER_PINNED, FILTER_ARCHIVED ]

// Archived chats live behind their own filter, so they are out of the way without being gone.
function kept(chats: AgentChat[], filter: string, search: string): AgentChat[] {
  const wanted = search.trim().toLowerCase()

  return chats.filter((chat) => {
    if (chat.archived !== (filter === FILTER_ARCHIVED)) {
      return false
    }
    if (filter === FILTER_PINNED && !chat.pinned) {
      return false
    }
    if (wanted.length === 0) {
      return true
    }

    return `${chat.title} ${chat.preview}`.toLowerCase().includes(wanted)
  })
}

export function ChatList({ chats, currentId, className }: ChatListProps) {
  const [ filter, setFilter ] = useState(FILTER_ALL)
  const [ search, setSearch ] = useState("")
  const field = useRef<HTMLInputElement>(null)
  const groups: ChatGroup[] = useMemo(() => groupedByDay(kept(chats, filter, search)), [ chats, filter, search ])
  useSearchShortcut(field)

  function startChat() {
    router.post(agentChatsPath())
  }

  return (
    <aside className={`min-h-0 flex-col gap-3 overflow-hidden border-r border-line px-3 py-3.5 ${className}`}>
      <div className="flex items-start justify-between gap-2 px-1">
        <div>
          <h2 className="flex items-center gap-1.5 text-[14px] font-medium text-ink">
            <IconMessageCircle className="size-4 text-ink-3" />
            Agent Chat
          </h2>
          <p className="mt-1 text-[12px] leading-snug text-ink-2">
            Ask about incidents, search your systems, start an investigation.
          </p>
        </div>
        <button
          type="button"
          onClick={startChat}
          aria-label="New chat"
          className="flex size-7 shrink-0 items-center justify-center rounded-control text-ink-2 shadow-btn transition-colors duration-100 hover:bg-hover hover:text-ink"
        >
          <IconPencilPlus className="size-4" />
        </button>
      </div>

      <label className="flex items-center gap-2 rounded-control bg-field px-2.5 py-2 shadow-inset-field">
        <IconSearch className="size-3.5 shrink-0 text-ink-3" />
        <input
          ref={field}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search chats"
          className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3"
        />
        <kbd className="shrink-0 rounded-chip px-1 font-mono text-[10.5px] text-ink-3 shadow-hairline">⌘K</kbd>
      </label>

      <div className="flex gap-1">
        {FILTERS.map((name) => (
          <button
            key={name}
            type="button"
            onClick={() => setFilter(name)}
            className={`rounded-chip px-2 py-1 text-[12px] transition-colors duration-100 ${
              filter === name ? "bg-hover-2 text-ink" : "text-ink-2 hover:bg-hover"
            }`}
          >
            {name}
          </button>
        ))}
      </div>

      <nav className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto">
        {groups.length === 0 && <p className="px-1 text-[12.5px] text-ink-3">Nothing here yet.</p>}
        {groups.map((group) => (
          <div key={group.label} className="flex flex-col gap-0.5">
            <p className="px-1 pb-1 text-[11px] font-medium uppercase tracking-wide text-ink-3">{group.label}</p>
            {group.chats.map((chat) => (
              <ChatRow key={chat.id} chat={chat} current={chat.id === currentId} />
            ))}
          </div>
        ))}
      </nav>
    </aside>
  )
}
