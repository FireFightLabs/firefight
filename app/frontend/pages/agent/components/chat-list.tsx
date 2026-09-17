import { Link, router } from "@inertiajs/react"
import { IconPencilPlus, IconPinFilled, IconSearch } from "@tabler/icons-react"
import { useMemo, useState } from "react"

import { agentChatPath, agentChatsPath } from "@/lib/routes"
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
  const groups: ChatGroup[] = useMemo(() => groupedByDay(kept(chats, filter, search)), [ chats, filter, search ])

  function startChat() {
    router.post(agentChatsPath())
  }

  return (
    <aside className={`shrink-0 flex-col gap-3 rounded-window bg-surface p-3 shadow-card ${className}`}>
      <div className="flex items-start justify-between gap-2">
        <div>
          <h2 className="text-[13.5px] font-medium text-ink">Agent Chat</h2>
          <p className="mt-0.5 text-[12px] leading-snug text-ink-2">
            Ask about incidents, search your systems, start an investigation.
          </p>
        </div>
        <button
          type="button"
          onClick={startChat}
          aria-label="New chat"
          className="flex size-7 shrink-0 items-center justify-center rounded-control text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
        >
          <IconPencilPlus className="size-4" />
        </button>
      </div>

      <label className="flex items-center gap-2 rounded-control bg-field px-2.5 py-1.5 shadow-inset-field">
        <IconSearch className="size-3.5 shrink-0 text-ink-3" />
        <input
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          placeholder="Search chats"
          className="min-w-0 flex-1 bg-transparent text-[12.5px] text-ink outline-none placeholder:text-ink-3"
        />
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

      <nav className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto">
        {groups.length === 0 && (
          <p className="px-1 text-[12.5px] text-ink-3">Nothing here yet.</p>
        )}
        {groups.map((group) => (
          <div key={group.label} className="flex flex-col gap-0.5">
            <p className="px-1 pb-1 text-[11.5px] font-medium text-ink-3">{group.label}</p>
            {group.chats.map((chat) => (
              <Link
                key={chat.id}
                href={agentChatPath(chat.id)}
                className={`flex flex-col gap-0.5 rounded-control px-2.5 py-2 transition-colors duration-100 ${
                  chat.id === currentId ? "bg-hover-2" : "hover:bg-hover"
                }`}
              >
                <span className="flex items-center gap-1.5">
                  {chat.pinned && <IconPinFilled className="size-3 shrink-0 text-ink-3" />}
                  <span className="truncate text-[12.5px] text-ink">{chat.title}</span>
                </span>
                {chat.preview.length > 0 && (
                  <span className="truncate text-[12px] text-ink-3">{chat.preview}</span>
                )}
              </Link>
            ))}
          </div>
        ))}
      </nav>
    </aside>
  )
}
