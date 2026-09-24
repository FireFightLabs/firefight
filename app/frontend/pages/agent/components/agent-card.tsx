import { AGENT_CARD_KINDS } from "@/lib/generated/constants"
import { IntegrationCard } from "@/pages/agent/components/integration-card"
import { InvestigationRunCard } from "@/pages/agent/components/investigation-run-card"
import type { AgentCard as AgentCardValue } from "@/pages/agent/types"

interface AgentCardProps {
  card: AgentCardValue
  // The tool call the card came from, which a run is found by.
  stepKey: string
}

// A tool result drawn as something other than text. Each kind is one component, chosen here.
export function AgentCard({ card, stepKey }: AgentCardProps) {
  if (card.kind === AGENT_CARD_KINDS.INTEGRATIONS && card.category) {
    return <IntegrationCard category={card.category} />
  }
  if (card.kind === AGENT_CARD_KINDS.INVESTIGATION) {
    return <InvestigationRunCard toolCallKey={stepKey} />
  }

  return null
}
