import { router } from "@inertiajs/react"
import { IconArchive, IconArchiveOff, IconPencil, IconPin, IconPinFilled, IconTrash } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { HeaderButton } from "@/pages/agent/components/header-button"
import { agentChatPath } from "@/lib/routes"
import { RenameChatDialog } from "@/pages/agent/components/rename-chat-dialog"
import { startedAt } from "@/pages/agent/lib/format-time"
import type { AgentChat } from "@/types/serializers"

interface ThreadHeaderProps {
  chat: AgentChat
  startedIso?: string
}

export function ThreadHeader({ chat, startedIso }: ThreadHeaderProps) {
  const [ renaming, setRenaming ] = useState(false)
  const [ deleting, setDeleting ] = useState(false)

  function rename(title: string) {
    setRenaming(false)
    router.patch(agentChatPath(chat.id), { title })
  }

  function togglePin() {
    router.patch(agentChatPath(chat.id), { pinned: !chat.pinned })
  }

  function toggleArchive() {
    router.patch(agentChatPath(chat.id), { archived: !chat.archived })
  }

  function remove() {
    setDeleting(false)
    router.delete(agentChatPath(chat.id))
  }

  function openRename() {
    setRenaming(true)
  }

  function openDelete() {
    setDeleting(true)
  }

  function closeRename() {
    setRenaming(false)
  }

  function closeDelete() {
    setDeleting(false)
  }

  return (
    <header className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
      <div className="min-w-0">
        <h1 className="truncate text-[14px] font-medium text-ink">{chat.title}</h1>
        {startedIso && <p className="mt-0.5 text-[12px] text-ink-3">Started {startedAt(startedIso)}</p>}
      </div>
      <div className="flex shrink-0 items-center gap-0.5">
        <HeaderButton label="Rename chat" onClick={openRename}>
          <IconPencil className="size-4" />
        </HeaderButton>
        <HeaderButton label={chat.pinned ? "Unpin chat" : "Pin chat"} onClick={togglePin}>
          {chat.pinned ? <IconPinFilled className="size-4" /> : <IconPin className="size-4" />}
        </HeaderButton>
        <HeaderButton label={chat.archived ? "Put back in the list" : "Archive chat"} onClick={toggleArchive}>
          {chat.archived ? <IconArchiveOff className="size-4" /> : <IconArchive className="size-4" />}
        </HeaderButton>
        <HeaderButton label="Delete chat" onClick={openDelete}>
          <IconTrash className="size-4" />
        </HeaderButton>
      </div>

      <RenameChatDialog open={renaming} title={chat.title} onRename={rename} onCancel={closeRename} />
      <ConfirmDeleteDialog
        open={deleting}
        title="Delete this chat?"
        description="The questions and the agent's answers go with it. This cannot be undone."
        onConfirm={remove}
        onCancel={closeDelete}
      />
    </header>
  )
}
