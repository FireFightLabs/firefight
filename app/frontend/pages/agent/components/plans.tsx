import { PlanCard } from "@/pages/agent/components/plan-card"
import type { AgentChatPlan } from "@/types/serializers"

export function Plans({ conversationId, plans }: { conversationId: string; plans: AgentChatPlan[] | undefined }) {
  return plans?.map((plan) => <PlanCard key={plan.id} conversationId={conversationId} plan={plan} />)
}
