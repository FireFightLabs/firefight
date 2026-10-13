import { WorkflowCard } from "@/pages/agent/components/workflow-card"
import type { AgentChatWorkflow } from "@/types/serializers"

export function WorkflowCards({ conversationId, workflows }: { conversationId: string; workflows: AgentChatWorkflow[] | undefined }) {
  return workflows?.map((workflow) => <WorkflowCard key={workflow.id} conversationId={conversationId} workflow={workflow} />)
}
