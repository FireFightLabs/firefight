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

// Searching opens a dialog over the page rather than filtering the list in place, so the list never
// jumps. The last thing said is searched too, so a chat is found by its latest answer as well as its title.
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
      description="Find a chat by its name or the last thing said in it."
      className="agent-search sm:max-w-2xl"
    >
      <CommandInput placeholder="Search chats" />
      <CommandList>
        <CommandEmpty>No chat matches that.</CommandEmpty>
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
