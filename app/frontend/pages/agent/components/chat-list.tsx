import { InfiniteScroll, router } from "@inertiajs/react"
import { type Icon, IconChevronRight, IconPencilPlus, IconSearch } from "@tabler/icons-react"
import { useCallback, useState } from "react"

import { agentChatsPath } from "@/lib/routes"
import { ChatListSection } from "@/pages/agent/components/chat-list-section"
import { ChatSearch } from "@/pages/agent/components/chat-search"
import { useSearchShortcut } from "@/pages/agent/hooks/use-search-shortcut"
import type { AgentChat } from "@/types/serializers"

// The page prop the list scrolls through, and how far ahead of its end the next page is asked for.
const CHATS_PROP = "conversations"
const SCROLL_BUFFER_PX = 200

interface ChatListProps {
  chats: AgentChat[]
  archivedCount: number
  currentId?: string
  className: string
}

// Pinned chats come first, then the rest by when they were last spoken to. Archived ones sort last and
// fold away at the bottom, open whenever the chat on screen is one of them. Their count comes from the
// server, since the list may not have scrolled far enough to load them all.
export function ChatList({ chats: loaded, archivedCount, currentId, className }: ChatListProps) {
  const chats = uniqueById(loaded)
  const pinned = chats.filter((chat) => chat.pinned && !chat.archived)
  const recent = chats.filter((chat) => !chat.pinned && !chat.archived)
  const archived = chats.filter((chat) => chat.archived)
  const currentIsArchived = archived.some((chat) => chat.id === currentId)

  const [ searching, setSearching ] = useState(false)
  const [ showArchived, setShowArchived ] = useState(currentIsArchived)
  const openSearch = useCallback(() => setSearching(true), [])
  useSearchShortcut(openSearch)

  // Already on an empty chat, there is nothing new to open.
  function startChat() {
    if (!currentId) {
      return
    }

    router.visit(agentChatsPath())
  }

  function toggleArchived() {
    setShowArchived((shown) => !shown)
  }

  return (
    <aside className={`min-h-0 flex-col gap-4 overflow-hidden border-r border-line px-2 py-3 ${className}`}>
      <div className="flex items-center justify-between px-2">
        <h2 className="text-[14px] font-medium text-ink">Chat</h2>
        <div className="flex items-center gap-0.5">
          <ListButton icon={IconSearch} label="Search chats" onClick={openSearch} />
          <ListButton icon={IconPencilPlus} label="New chat" onClick={startChat} />
        </div>
      </div>

      <nav className="min-h-0 flex-1 overflow-y-auto">
        <InfiniteScroll
          data={CHATS_PROP}
          preserveUrl
          onlyNext
          buffer={SCROLL_BUFFER_PX}
          className="flex flex-col gap-4"
          loading={<p className="px-2.5 text-[12px] text-ink-3">Loading more chats</p>}
        >
          {chats.length === 0 && <p className="px-2.5 text-[12.5px] text-ink-3">No chats yet.</p>}
          <ChatListSection label="Pinned" chats={pinned} currentId={currentId} />
          <ChatListSection label={pinned.length > 0 ? "Chats" : undefined} chats={recent} currentId={currentId} />

          {archivedCount > 0 && (
            <div className="flex flex-col gap-0.5">
              <button
                type="button"
                onClick={toggleArchived}
                aria-expanded={showArchived}
                className="flex items-center gap-1 px-2.5 pb-1 text-[12px] text-ink-3 transition-colors duration-100 hover:text-ink-2"
              >
                <IconChevronRight className={`size-3.5 transition-transform duration-100 ${showArchived ? "rotate-90" : ""}`} />
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

interface ListButtonProps {
  icon: Icon
  label: string
  onClick: () => void
}

function ListButton({ icon: ButtonIcon, label, onClick }: ListButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="flex size-7 items-center justify-center rounded-control text-ink-2 transition-colors duration-100 hover:bg-hover hover:text-ink"
    >
      <ButtonIcon className="size-4" />
    </button>
  )
}

// A chat that moves up the list while more pages load can arrive twice. The first copy is the newer one.
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
