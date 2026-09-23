import { AGENT_CARD_KINDS } from "@/lib/generated/constants"
import { IntegrationCard } from "@/pages/agent/components/integration-card"
import type { AgentCard as AgentCardValue } from "@/pages/agent/types"

interface AgentCardProps {
  card: AgentCardValue
}

// A tool result drawn as something other than text. Each kind is one component, chosen here.
export function AgentCard({ card }: AgentCardProps) {
  if (card.kind === AGENT_CARD_KINDS.INTEGRATIONS) {
    return <IntegrationCard category={card.category} />
  }

  return null
}
