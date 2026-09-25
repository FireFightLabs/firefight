import { Link, usePage } from "@inertiajs/react"
import { IconFlame, IconHierarchy2, IconMessages, IconSparkles, type Icon } from "@tabler/icons-react"

import { Card } from "@/components/ui/card"
import { OPERATOR_FIND_KINDS } from "@/lib/generated/constants"
import { OperatorLayout } from "@/pages/operator/components/operator-layout"
import { PageHeading } from "@/pages/operator/components/page-heading"
import type { OperatorPageProps } from "@/pages/operator/types"
import type { OperatorFindMatch } from "@/types/serializers"

interface FindProps extends OperatorPageProps {
  query: string
  matches: OperatorFindMatch[]
}

const KINDS: Record<OperatorFindMatch["kind"], { label: string; icon: Icon }> = {
  [OPERATOR_FIND_KINDS.INCIDENT]: { label: "Incident", icon: IconFlame },
  [OPERATOR_FIND_KINDS.RUN]: { label: "Halon run", icon: IconSparkles },
  [OPERATOR_FIND_KINDS.CHAT]: { label: "Halon chat", icon: IconMessages },
  [OPERATOR_FIND_KINDS.WORKFLOW]: { label: "Workflow", icon: IconHierarchy2 },
}

function matchesFor(count: number): string {
  if (count === 0) {
    return "Nothing matches "
  }
  return count === 1 ? "1 match for " : `${count} matches for `
}

function MatchRow({ match }: { match: OperatorFindMatch }) {
  const kind = KINDS[match.kind]
  const KindIcon = kind.icon

  return (
    <li className="border-b border-border last:border-b-0">
      <Link href={match.href} className="hover:bg-muted/40 flex items-start gap-4 px-5 py-3.5">
        <KindIcon className="text-primary mt-0.5 size-4 shrink-0" stroke={1.7} />
        <span className="flex min-w-0 flex-col gap-0.5">
          <span className="truncate text-sm font-medium">{match.label}</span>
          <span className="text-muted-foreground text-xs">
            {kind.label} · {match.place}
          </span>
          {match.via && <span className="text-muted-foreground font-mono text-xs">found by {match.via}</span>}
        </span>
      </Link>
    </li>
  )
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
