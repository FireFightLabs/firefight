import { Link } from "@inertiajs/react"

import { formatDateTime } from "@/lib/formatters"
import { incidentPath, investigationsPath } from "@/lib/routes"
import { InvestigationStatusBadge } from "@/pages/investigations/components/investigation-status-badge"
import { formatSeconds, formatSpend } from "@/pages/investigations/lib/format"
import { TRIGGER_LABELS, labelFor } from "@/pages/investigations/lib/labels"
import type { InvestigationDetail } from "@/types/serializers"

export function InvestigationHeader({ investigation }: { investigation: InvestigationDetail }) {
  const asked = [
    investigation.askedBy ? `Asked by ${investigation.askedBy}` : "Started",
    `through ${labelFor(TRIGGER_LABELS, investigation.trigger)}`,
    formatDateTime(investigation.createdAt),
  ].join(" ")

  return (
    <header className="flex flex-col gap-3">
      <Link href={investigationsPath()} className="text-muted-foreground text-sm hover:underline">
        All investigations
      </Link>
      <div className="flex flex-wrap items-center gap-3">
        <h1 className="text-xl font-semibold">
          {investigation.incidentId ? (
            <Link href={incidentPath(investigation.incidentId)} className="hover:underline">
              {investigation.incidentIdentifier} {investigation.incidentName}
            </Link>
          ) : (
            "Investigation"
          )}
        </h1>
        <InvestigationStatusBadge status={investigation.status} />
      </div>
      <p className="text-muted-foreground text-sm">{asked}</p>
      <dl className="text-muted-foreground flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <div className="flex gap-1.5">
          <dt>Took</dt>
          <dd className="text-foreground">{formatSeconds(investigation.durationSeconds)}</dd>
        </div>
        <div className="flex gap-1.5">
          <dt>Spent</dt>
          <dd className="text-foreground">
            {formatSpend(investigation.spentCents)} of {formatSpend(investigation.maxSpendCents)}
          </dd>
        </div>
        <div className="flex gap-1.5">
          <dt>Turns</dt>
          <dd className="text-foreground">{investigation.turnsUsed}</dd>
        </div>
        <div className="flex gap-1.5">
          <dt>Steps</dt>
          <dd className="text-foreground">{investigation.steps.length}</dd>
        </div>
      </dl>
      {investigation.brief && (
        <blockquote className="text-muted-foreground border-l-2 pl-3 text-sm">{investigation.brief}</blockquote>
      )}
    </header>
  )
}
