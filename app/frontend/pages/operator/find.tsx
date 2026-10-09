import { usePage } from "@inertiajs/react"

import { Card } from "@/components/ui/card"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorFindMatch } from "@/types/serializers"
import { MatchRow } from "@/pages/operator/components/match-row"

interface FindProps extends OperatorPageProps {
  query: string
  matches: OperatorFindMatch[]
}

function matchesFor(count: number): string {
  if (count === 0) {
    return "Nothing matches "
  }
  return count === 1 ? "1 match for " : `${count} matches for `
}

export default function OperatorFind() {
  const { query, matches } = usePage<FindProps>().props

  return (
    <OperatorLayout title="Find">
      <PageHeading
        title="Find"
        lead="Anything with an id: an incident, a Halon run or chat, a workflow, and the records inside them such as a model call, a tool call, a ledger entry or a webhook delivery. The start of an id works too, and an incident number is looked up in every workspace."
      />
      <Card className="gap-0 overflow-hidden py-0">
        <div className="border-b border-border px-5 py-4 text-sm">
          {matchesFor(matches.length)}
          <span className="font-mono">{query}</span>
        </div>
        {matches.length === 0 ? (
          <p className="text-muted-foreground px-5 py-8 text-sm">
            Paste a whole id, at least its first 6 characters, or an incident number such as INC-042.
          </p>
        ) : (
          <ul className="list-none">
            {matches.map((match) => (
              <MatchRow key={`${match.kind}-${match.id}-${match.via ?? ""}`} match={match} />
            ))}
          </ul>
        )}
      </Card>
    </OperatorLayout>
  )
}
