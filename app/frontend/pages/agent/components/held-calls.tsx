import { HeldCallCard } from "@/pages/agent/components/held-call-card"
import type { AgentChatHeldCall } from "@/types/serializers"

export function HeldCalls({ conversationId, heldCalls }: { conversationId: string; heldCalls: AgentChatHeldCall[] | undefined }) {
  return heldCalls?.map((heldCall) => <HeldCallCard key={heldCall.id} conversationId={conversationId} heldCall={heldCall} />)
}
