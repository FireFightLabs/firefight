import { router } from "@inertiajs/react"
import { IconDotsVertical } from "@tabler/icons-react"
import { useState } from "react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { agentChatPath } from "@/lib/routes"
import { RenameChatDialog } from "@/pages/agent/components/rename-chat-dialog"
import type { AgentChat } from "@/types/serializers"

interface ChatRowActionsProps {
  chat: AgentChat
  className: string
}

export function ChatRowActions({ chat, className }: ChatRowActionsProps) {
  const [ renaming, setRenaming ] = useState(false)
  const [ deleting, setDeleting ] = useState(false)

  function rename(title: string) {
    setRenaming(false)
    router.patch(agentChatPath(chat.id), { title }, { preserveScroll: true })
  }

  function togglePin() {
    router.patch(agentChatPath(chat.id), { pinned: !chat.pinned }, { preserveScroll: true })
  }

  function toggleArchive() {
    router.patch(agentChatPath(chat.id), { archived: !chat.archived }, { preserveScroll: true })
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
    <>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <button
            type="button"
            aria-label={`Actions for ${chat.title}`}
            className={`flex size-6 items-center justify-center rounded-chip text-ink-3 transition-colors duration-100 hover:bg-hover-2 hover:text-ink ${className}`}
          >
            <IconDotsVertical className="size-4" />
          </button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-36">
          <DropdownMenuItem onClick={openRename}>Rename</DropdownMenuItem>
          <DropdownMenuItem onClick={togglePin}>{chat.pinned ? "Unpin" : "Pin"}</DropdownMenuItem>
          <DropdownMenuItem onClick={toggleArchive}>{chat.archived ? "Unarchive" : "Archive"}</DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem variant="destructive" onClick={openDelete}>Delete</DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      <RenameChatDialog chatId={chat.id} open={renaming} title={chat.title} onRename={rename} onCancel={closeRename} />
      <ConfirmDeleteDialog
        open={deleting}
        title="Delete this chat?"
        description="The questions and the agent's answers go with it. This cannot be undone."
        onConfirm={remove}
        onCancel={closeDelete}
      />
    </>
  )
}
