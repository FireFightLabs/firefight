import { WatchCard } from "@/pages/agent/components/watch-card"
import { WatchUpdate } from "@/pages/agent/components/watch-update"
import type { AgentChatWatch, AgentChatWatchUpdate } from "@/types/serializers"

interface WatchesProps {
  conversationId: string
  watches: AgentChatWatch[] | undefined
  updates: AgentChatWatchUpdate[] | undefined
}

// The card first, then what was said since, so a line said after the answer reads below the card that started it.
export function Watches({ conversationId, watches, updates }: WatchesProps) {
  return (
    <>
      {watches?.map((watch) => <WatchCard key={watch.id} conversationId={conversationId} watch={watch} />)}
      {updates?.map((update) => <WatchUpdate key={update.id} update={update} />)}
    </>
  )
}
