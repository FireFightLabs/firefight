import { IconMessage } from "@tabler/icons-react"
import { useState } from "react"

import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from "@/components/ui/command"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { agentChatsSearchPath } from "@/lib/routes"
import { useRemoteSearch } from "@/pages/agent/hooks/use-remote-search"
import { openChat } from "@/pages/agent/lib/chat-updates"
import type { AgentChat } from "@/types/serializers"

interface ChatSearchProps {
  chats: AgentChat[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

function searchPath(query: string) {
  return agentChatsSearchPath({ q: query })
}

export function ChatSearch({ chats, open, onOpenChange }: ChatSearchProps) {
  const [ query, setQuery ] = useState("")
  const { results, search } = useRemoteSearch<AgentChat>(searchPath)
  const shown = results ?? chats

  // The server filters, so the first result is selected here for Enter to open it.
  const shownIds = shown.map((chat) => chat.id).join(" ")
  const [ selected, setSelected ] = useState(shown[0]?.id ?? "")
  const [ selectedFor, setSelectedFor ] = useState(shownIds)
  if (shownIds !== selectedFor) {
    setSelectedFor(shownIds)
    setSelected(shown[0]?.id ?? "")
  }

  function changeQuery(next: string) {
    setQuery(next)
    search(next)
  }

  function choose(chat: AgentChat) {
    onOpenChange(false)
    openChat(chat.id)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogHeader className="sr-only">
        <DialogTitle>Search chats</DialogTitle>
        <DialogDescription>Find a chat by its name or the last thing said in it.</DialogDescription>
      </DialogHeader>
      <DialogContent className="agent-search overflow-hidden p-0 sm:max-w-2xl">
        <Command
          shouldFilter={false}
          value={selected}
          onValueChange={setSelected}
          className="**:data-[slot=command-input-wrapper]:h-12 [&_[cmdk-group-heading]]:px-2 [&_[cmdk-group-heading]]:font-medium [&_[cmdk-group-heading]]:text-muted-foreground [&_[cmdk-group]]:px-2 [&_[cmdk-item]]:px-2 [&_[cmdk-item]]:py-3"
        >
          <CommandInput placeholder="Search chats" value={query} onValueChange={changeQuery} />
          <CommandList>
            <CommandEmpty>No chat matches that.</CommandEmpty>
            <CommandGroup heading={results ? "Matching chats" : "Recent chats"}>
              {shown.map((chat) => (
                <CommandItem key={chat.id} value={chat.id} onSelect={() => choose(chat)}>
                  <IconMessage className="size-4 text-muted-foreground" />
                  <span className="truncate">{chat.title}</span>
                </CommandItem>
              ))}
            </CommandGroup>
          </CommandList>
        </Command>
      </DialogContent>
    </Dialog>
  )
}
