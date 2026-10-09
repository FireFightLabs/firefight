import { PackRefusalCard } from "@/pages/agent/components/pack-refusal-card"
import type { AgentChatPackRefusal } from "@/types/serializers"

export function PackRefusals({ conversationId, refusals }: { conversationId: string; refusals: AgentChatPackRefusal[] | undefined }) {
  return refusals?.map((refusal) => <PackRefusalCard key={refusal.id} conversationId={conversationId} refusal={refusal} />)
}
