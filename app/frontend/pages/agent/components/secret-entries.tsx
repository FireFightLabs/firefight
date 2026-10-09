import { SecretEntryCard } from "@/pages/agent/components/secret-entry-card"
import type { AgentChatSecretEntry } from "@/types/serializers"

export function SecretEntries({ conversationId, entries }: { conversationId: string; entries: AgentChatSecretEntry[] | undefined }) {
  return entries?.map((entry) => <SecretEntryCard key={entry.id} conversationId={conversationId} entry={entry} />)
}
