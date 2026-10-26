import { type Icon, IconChartLine, IconCode, IconFileText, IconFlame, IconTopologyStar3 } from "@tabler/icons-react"

import type { ReviewEvidenceKind } from "@/lib/generated/constants"
import { newTabAttributes } from "@/lib/links"
import type { HalonPreventedEvidence } from "@/types/serializers"

const EVIDENCE_ICONS: Record<ReviewEvidenceKind, Icon> = {
  incident: IconFlame,
  postmortem: IconFileText,
  map_resource: IconTopologyStar3,
  metric: IconChartLine,
  code: IconCode,
}

// One thing the review cited, opened where it lives when it has an address.
export function PreventedEvidence({ evidence }: { evidence: HalonPreventedEvidence }) {
  const KindIcon = EVIDENCE_ICONS[evidence.kind]

  return (
    <li className="flex items-start gap-1.5 text-sm text-fg-body">
      <KindIcon className="mt-0.5 size-3.5 shrink-0 text-fg-secondary" />
      {evidence.url ? (
        <a href={evidence.url} {...newTabAttributes(evidence.url)} className="text-link underline underline-offset-2">
          {evidence.title}
        </a>
      ) : (
        <span>{evidence.title}</span>
      )}
    </li>
  )
}
