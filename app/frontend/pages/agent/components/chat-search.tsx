import { router } from "@inertiajs/react"
import { IconMessage } from "@tabler/icons-react"

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command"
import { agentChatPath } from "@/lib/routes"
import type { AgentChat } from "@/types/serializers"

interface ChatSearchProps {
  chats: AgentChat[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

// Searching chats opens over the page, the way it does in ChatGPT, rather than filtering the list in
// place. What was last said is searched too, so a chat is found by its answer as well as its title.
// It is drawn with the app's own dialog tokens, since it opens outside the chat's scoped palette.
export function ChatSearch({ chats, open, onOpenChange }: ChatSearchProps) {
  function openChat(chat: AgentChat) {
    onOpenChange(false)
    router.visit(agentChatPath(chat.id))
  }

  return (
    <CommandDialog
      open={open}
      onOpenChange={onOpenChange}
      title="Search chats"
      description="Find a chat by what was asked or answered."
      className="agent-search sm:max-w-2xl"
    >
      <CommandInput placeholder="Search chats" />
      <CommandList>
        <CommandEmpty>No chat says that.</CommandEmpty>
        <CommandGroup heading="Recent chats">
          {chats.map((chat) => (
            <CommandItem
              key={chat.id}
              value={`${chat.title} ${chat.preview} ${chat.id}`}
              onSelect={() => openChat(chat)}
            >
              <IconMessage className="size-4 text-muted-foreground" />
              <span className="truncate">{chat.title}</span>
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  )
}
