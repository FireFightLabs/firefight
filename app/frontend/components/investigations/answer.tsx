import { IconAlertTriangle, IconCircleCheck, IconLoader2 } from "@tabler/icons-react"
import type { ReactNode } from "react"

import { Button } from "@/components/ui/button"
import { FixPlan } from "@/components/investigations/fix-plan"
import { RateAnswer } from "@/components/investigations/rate-answer"
import { StepLinks } from "@/components/investigations/step-links"
import { OUTCOME_LABELS, labelFor } from "@/components/investigations/labels"
import { isLive } from "@/components/investigations/use-live-investigation"
import type { InvestigationDetail } from "@/types/serializers"

function Part({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid gap-1.5 sm:grid-cols-[8.5rem_1fr] sm:gap-4">
      <h3 className="pt-0.5 text-[11px] font-medium tracking-[0.15em] text-fg-muted uppercase">{label}</h3>
      <div className="min-w-0 text-sm leading-relaxed text-fg-body">{children}</div>
    </div>
  )
}

function Heading({ children }: { children: ReactNode }) {
  return <div className="flex items-center gap-2 text-[11px] font-semibold tracking-[0.18em] uppercase">{children}</div>
}

// Every state of the answer is the same card. A 2px bar and the heading carry the state's colour, the text stays readable.
const FRAMES = {
  working: "edge-bar [--edge-bar-inset:12px] [--edge-bar:var(--stage-active)]",
  stopped: "edge-bar [--edge-bar-inset:12px] [--edge-bar:var(--warning)]",
  answered: "edge-bar [--edge-bar-inset:12px] [--edge-bar:var(--success)]",
}

const FRAME = "rounded-xl border border-border bg-surface-card p-5 transition-colors duration-200"

// The answer first, since it is what someone opening a run came for. While it works, what it is doing. When it
// stopped, why.
interface AnswerProps {
  investigation: InvestigationDetail
  onDeclare?: () => void
}

export function Answer({ investigation, onDeclare }: AnswerProps) {
  const finding = investigation.finding

  if (!finding && isLive(investigation.status)) {
    const current = investigation.steps[investigation.steps.length - 1]
    return (
      <section className={`${FRAME} ${FRAMES.working}`}>
        <Heading>
          <span className="flex items-center gap-2 text-stage-active">
            <IconLoader2 className="size-3.5 motion-safe:animate-spin" />
            Investigating
          </span>
        </Heading>
        <p className="mt-3 text-sm text-fg-body">
          {current ? `Now on step ${current.position}, ${current.label}.` : "Reading what Firefight already knows."}
        </p>
      </section>
    )
  }

  if (!finding) {
    return (
      <section className={`${FRAME} ${FRAMES.stopped}`}>
        <Heading>
          <span className="flex items-center gap-2 text-warning">
            <IconAlertTriangle className="size-3.5" />
            No answer
          </span>
        </Heading>
        <p className="mt-3 text-sm text-fg-body">{investigation.stoppedBecause ?? "Stopped without an answer."}</p>
      </section>
    )
  }

  const verdicts = Object.entries(finding.verdicts)

  return (
    <section className={`${FRAME} ${FRAMES.answered}`}>
      <Heading>
        <span className="flex items-center gap-2 text-success">
          <IconCircleCheck className="size-3.5" />
          Answer
        </span>
      </Heading>
      <p className="mt-3 text-base leading-relaxed text-fg-primary text-pretty">{finding.summary}</p>
      {finding.suggestsIncident && !investigation.incidentId && onDeclare && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 edge-bar rounded-lg bg-error-tint px-4 py-3 [--edge-bar-inset:8px] [--edge-bar:var(--error)]">
          <span className="flex items-center gap-2 text-sm text-fg-primary">
            <IconAlertTriangle className="size-4 shrink-0 text-error" />
            Halon thinks this is hurting users now.
          </span>
          <Button size="sm" onClick={onDeclare}>
            Declare incident
          </Button>
        </div>
      )}

      <div className="mt-5 flex flex-col gap-4 border-t border-border pt-5">
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
        {finding.fix && (
          <Part label="How to fix it">
            <FixPlan investigationId={investigation.id} fix={finding.fix} />
          </Part>
        )}
        {finding.fix?.undo && (
          <Part label="How to undo it">
            <FixPlan investigationId={investigation.id} fix={finding.fix.undo} />
          </Part>
        )}
        {finding.gaps && (
          <Part label="Could not check">
            <span className="text-fg-secondary">{finding.gaps}</span>
          </Part>
        )}
        {(finding.outcome || verdicts.length > 0) && (
          <Part label="The team says">
            <span className="text-fg-secondary">
              {finding.outcome
                ? labelFor(OUTCOME_LABELS, finding.outcome)
                : verdicts.map(([outcome, count]) => `${count} ${labelFor(OUTCOME_LABELS, outcome)?.toLowerCase()}`).join(", ")}
            </span>
          </Part>
        )}
        <Part label="Was it right?">
          <RateAnswer investigationId={investigation.id} mine={finding.myVerdict} />
        </Part>
      </div>
    </section>
  )
}
