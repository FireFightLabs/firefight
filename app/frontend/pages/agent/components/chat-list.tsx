import { router } from "@inertiajs/react"
import { IconChevronRight, IconPencilPlus, IconSearch } from "@tabler/icons-react"
import { useCallback, useState } from "react"

import { agentChatsPath } from "@/lib/routes"
import { ChatListSection } from "@/pages/agent/components/chat-list-section"
import { ChatSearch } from "@/pages/agent/components/chat-search"
import { useSearchShortcut } from "@/pages/agent/hooks/use-search-shortcut"
import type { AgentChat } from "@/types/serializers"

interface ChatListProps {
  chats: AgentChat[]
  currentId?: string
  className: string
}

// Laid out the way ChatGPT lays out its history: pinned chats first, then the rest, and archived ones
// folded away at the bottom where they are reachable without being in the way.
export function ChatList({ chats, currentId, className }: ChatListProps) {
  const [ searching, setSearching ] = useState(false)
  const [ showArchived, setShowArchived ] = useState(false)
  const openSearch = useCallback(() => setSearching(true), [])
  useSearchShortcut(openSearch)

  const pinned = chats.filter((chat) => chat.pinned && !chat.archived)
  const recent = chats.filter((chat) => !chat.pinned && !chat.archived)
  const archived = chats.filter((chat) => chat.archived)

  function startChat() {
    router.post(agentChatsPath())
  }

  function toggleArchived() {
    setShowArchived((shown) => !shown)
  }

  return (
    <aside className={`min-h-0 flex-col gap-4 overflow-hidden border-r border-line px-2 py-3 ${className}`}>
      <div className="flex items-center justify-between px-2">
        <h2 className="text-[14px] font-medium text-ink">Agent</h2>
        <div className="flex items-center gap-0.5">
          <button
            type="button"
            onClick={openSearch}
            aria-label="Search chats"
            title="Search chats (⌘K)"
            className="flex size-7 items-center justify-center rounded-control text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
          >
            <IconSearch className="size-4" />
          </button>
          <button
            type="button"
            onClick={startChat}
            aria-label="New chat"
            title="New chat"
            className="flex size-7 items-center justify-center rounded-control text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
          >
            <IconPencilPlus className="size-4" />
          </button>
        </div>
      </div>

      <nav className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto">
        {chats.length === 0 && <p className="px-2.5 text-[12.5px] text-ink-3">No chats yet.</p>}
        <ChatListSection label="Pinned" chats={pinned} currentId={currentId} />
        <ChatListSection label="Chats" chats={recent} currentId={currentId} />

        {archived.length > 0 && (
          <div className="flex flex-col gap-0.5">
            <button
              type="button"
              onClick={toggleArchived}
              aria-expanded={showArchived}
              className="flex items-center gap-1 px-2.5 pb-1 text-[12px] text-ink-3 transition-colors duration-100 hover:text-ink-2"
            >
              <IconChevronRight className={`size-3.5 transition-transform duration-100 ${showArchived ? "rotate-90" : ""}`} />
              Archived ({archived.length})
            </button>
            {showArchived && <ChatListSection chats={archived} currentId={currentId} />}
          </div>
        )}
      </nav>

      <ChatSearch chats={chats} open={searching} onOpenChange={setSearching} />
    </aside>
  )
}
