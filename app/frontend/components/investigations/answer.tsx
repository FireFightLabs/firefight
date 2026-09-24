import { IconAlertTriangle, IconCircleCheck, IconLoader2 } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { StepLinks } from "@/components/investigations/step-links"
import { OUTCOME_LABELS, labelFor } from "@/components/investigations/labels"
import { TONE_CLASSES } from "@/components/investigations/tone"
import { isLive } from "@/components/investigations/use-live-investigation"
import type { InvestigationDetail } from "@/types/serializers"

function Part({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-1.5 sm:grid-cols-[8.5rem_1fr] sm:gap-4">
      <h3 className="pt-0.5 text-[11px] font-medium tracking-[0.15em] text-muted-foreground/80 uppercase">{label}</h3>
      <div className="min-w-0 text-sm leading-relaxed">{children}</div>
    </div>
  )
}

function Heading({ children }: { children: ReactNode }) {
  return <div className="flex items-center gap-2 text-[11px] font-semibold tracking-[0.18em] uppercase">{children}</div>
}

// The answer first, since it is what someone opening a run came for. While it works, what it is doing. When it
// stopped, why.
export function Answer({ investigation }: { investigation: InvestigationDetail }) {
  const finding = investigation.finding

  if (!finding && isLive(investigation.status)) {
    const current = investigation.steps[investigation.steps.length - 1]
    return (
      <section className={`rounded-xl border p-5 ${TONE_CLASSES.primary}`}>
        <Heading>
          <IconLoader2 className="size-3.5 animate-spin" />
          Investigating
        </Heading>
        <p className="mt-3 text-sm text-foreground">
          {current ? `Now on step ${current.position}, ${current.label}.` : "Reading what Firefight already knows."}
        </p>
      </section>
    )
  }

  if (!finding) {
    return (
      <section className={`rounded-xl border p-5 ${TONE_CLASSES.amber}`}>
        <Heading>
          <IconAlertTriangle className="size-3.5" />
          No answer
        </Heading>
        <p className="mt-3 text-sm text-foreground">{investigation.stoppedBecause ?? "Stopped without an answer."}</p>
      </section>
    )
  }

  const verdicts = Object.entries(finding.verdicts)

  return (
    <section className="rounded-xl border border-emerald-500/30 bg-emerald-500/[0.04] p-5 dark:border-emerald-400/30 dark:bg-emerald-400/[0.04]">
      <Heading>
        <span className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
          <IconCircleCheck className="size-3.5" />
          Answer
        </span>
      </Heading>
      <p className="mt-3 text-base leading-relaxed text-foreground text-pretty">{finding.summary}</p>

      <div className="mt-5 flex flex-col gap-4 border-t border-emerald-500/20 pt-5">
        {finding.cause && <Part label="Cause">{finding.cause}</Part>}
        {finding.evidence.length > 0 && (
          <Part label="Why it thinks so">
            <ul className="flex flex-col gap-2.5">
              {finding.evidence.map((item) => (
                <li key={item.id} className="flex flex-col gap-1">
                  <span>{item.claim}</span>
                  <StepLinks steps={item.steps} />
                </li>
              ))}
            </ul>
          </Part>
        )}
        {finding.gaps && (
          <Part label="Could not check">
            <span className="text-muted-foreground">{finding.gaps}</span>
          </Part>
        )}
        {(finding.outcome || verdicts.length > 0) && (
          <Part label="The team says">
            <span className="text-muted-foreground">
              {finding.outcome
                ? labelFor(OUTCOME_LABELS, finding.outcome)
                : verdicts.map(([outcome, count]) => `${count} ${labelFor(OUTCOME_LABELS, outcome)?.toLowerCase()}`).join(", ")}
            </span>
          </Part>
        )}
      </div>
    </section>
  )
}
