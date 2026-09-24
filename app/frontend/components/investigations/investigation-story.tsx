import type { ReactNode } from "react"

import { ActorChip } from "@/components/actor-chip"
import { formatDateTime } from "@/lib/formatters"
import { Answer } from "@/components/investigations/answer"
import { formatSeconds } from "@/components/investigations/format"
import { TRIGGER_LABELS, labelFor } from "@/components/investigations/labels"
import { RunStory } from "@/components/investigations/run-story"
import { InvestigationStatusBadge } from "@/components/investigations/status-badge"
import { Theories } from "@/components/investigations/theories"
import type { InvestigationDetail } from "@/types/serializers"

function Meta({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <div className="text-[11px] font-medium tracking-[0.18em] text-muted-foreground/70 uppercase">{label}</div>
      <div className="mt-1.5 truncate text-sm text-foreground">{children}</div>
    </div>
  )
}

function SectionHeading({ title, count }: { title: string; count?: number }) {
  return (
    <div className="mb-3 flex items-baseline gap-3">
      <h2 className="text-[11px] font-semibold tracking-[0.2em] text-foreground/90 uppercase">{title}</h2>
      {count != null && <span className="text-[11px] tabular-nums text-muted-foreground/70">{count}</span>}
    </div>
  )
}

export function investigationTitle(investigation: InvestigationDetail): string {
  return investigation.question ?? `What happened in ${investigation.incidentIdentifier ?? "this incident"}`
}

// One run told in order, with what it was asked, the answer, the theories it weighed and every step on the way.
// The same story is drawn over an incident, in a chat and on the run's own page, so it knows nothing of where.
interface InvestigationStoryProps {
  investigation: InvestigationDetail
  title: ReactNode
  // Offered where an incident can be declared from the answer.
  onDeclare?: () => void
}

export function InvestigationStory({ investigation, title, onDeclare }: InvestigationStoryProps) {
  return (
    <div className="flex flex-col gap-8">
      <header className="flex flex-col gap-4">
        <InvestigationStatusBadge status={investigation.status} />
        {title}
        <div className="grid grid-cols-2 gap-x-6 gap-y-4 border-y border-border py-4 sm:grid-cols-4">
          <Meta label="Asked by">
            <ActorChip actor={investigation.asker} fallback="-" />
          </Meta>
          <Meta label="From">{labelFor(TRIGGER_LABELS, investigation.trigger)}</Meta>
          <Meta label="Started">{formatDateTime(investigation.createdAt)}</Meta>
          <Meta label="Took">{formatSeconds(investigation.durationSeconds)}</Meta>
        </div>
      </header>

      <Answer investigation={investigation} onDeclare={onDeclare} />

      <section>
        <SectionHeading title="Theories" count={investigation.hypotheses.length} />
        <Theories hypotheses={investigation.hypotheses} />
      </section>

      <section>
        <SectionHeading title="How it got there" count={investigation.steps.length} />
        <RunStory investigation={investigation} />
      </section>
    </div>
  )
}
