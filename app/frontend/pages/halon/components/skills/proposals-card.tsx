import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import type { HalonSkillProposal } from "@/types/serializers"
import { ProposalItem } from "@/pages/halon/components/skills/proposal-item"

interface ProposalsCardProps {
  proposals: HalonSkillProposal[]
  canDecide: boolean
  onEdit: (proposal: HalonSkillProposal) => void
}

// The skills Halon proposed and nobody decided on yet, oldest first.
export function ProposalsCard({ proposals, canDecide, onEdit }: ProposalsCardProps) {
  return (
    <Card className="edge-bar [--edge-bar-inset:12px] [--edge-bar:var(--lime)]">
      <CardHeader>
        <CardTitle>Proposed by Halon</CardTitle>
        <CardDescription className="mt-1">
          Nothing changes until someone accepts. {proposals.length === 1 ? "One proposal waits." : `${proposals.length} proposals wait.`}
        </CardDescription>
      </CardHeader>
      <CardContent className="p-0">
        {proposals.map((proposal) => (
          <ProposalItem key={proposal.id} proposal={proposal} canDecide={canDecide} onEdit={onEdit} />
        ))}
      </CardContent>
    </Card>
  )
}
