import { Link } from "@inertiajs/react"
import { IconFlame, IconHierarchy2, IconMessages, IconSparkles, type Icon } from "@tabler/icons-react"

import { OPERATOR_FIND_KINDS } from "@/pages/operator/generated/constants"
import type { OperatorFindMatch } from "@/types/serializers"

const KINDS: Record<OperatorFindMatch["kind"], { label: string; icon: Icon }> = {
  [OPERATOR_FIND_KINDS.INCIDENT]: { label: "Incident", icon: IconFlame },
  [OPERATOR_FIND_KINDS.RUN]: { label: "Halon run", icon: IconSparkles },
  [OPERATOR_FIND_KINDS.CHAT]: { label: "Halon chat", icon: IconMessages },
  [OPERATOR_FIND_KINDS.WORKFLOW]: { label: "Workflow", icon: IconHierarchy2 },
}

export function MatchRow({ match }: { match: OperatorFindMatch }) {
  const kind = KINDS[match.kind]
  const KindIcon = kind.icon

  return (
    <li className="border-b border-border last:border-b-0">
      <Link href={match.href} className="hover:bg-surface-hover transition-colors flex items-start gap-4 px-5 py-3.5">
        <KindIcon className="text-fg-secondary mt-0.5 size-4 shrink-0" stroke={1.7} />
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
