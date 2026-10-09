import { IconAlertTriangle, IconCircleCheck, IconLoader2 } from "@tabler/icons-react"
import { Button } from "@/components/ui/button"
import { AnswerHeading } from "@/components/investigations/answer-heading"
import { AnswerPart } from "@/components/investigations/answer-part"
import { IncidentsBlocked, useIncidentsBlockedReason } from "@/components/incidents/incidents-blocked"
import { FixPlan } from "@/components/investigations/fix-plan"
import { RateAnswer } from "@/components/investigations/rate-answer"
import { StepLinks } from "@/components/investigations/step-links"
import { OUTCOME_LABELS, labelFor } from "@/components/investigations/labels"
import { isLive } from "@/components/investigations/use-live-investigation"
import type { InvestigationDetail } from "@/types/serializers"

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
  const declareBlockedReason = useIncidentsBlockedReason()

  if (!finding && isLive(investigation.status)) {
    const current = investigation.steps[investigation.steps.length - 1]
    return (
      <section className={`${FRAME} ${FRAMES.working}`}>
        <AnswerHeading>
          <span className="flex items-center gap-2 text-stage-active">
            <IconLoader2 className="size-3.5 motion-safe:animate-spin" />
            Investigating
          </span>
        </AnswerHeading>
        <p className="mt-3 text-sm text-fg-body">
          {current ? `Now on step ${current.position}, ${current.label}.` : "Reading what Firefight already knows."}
        </p>
      </section>
    )
  }

  if (!finding) {
    return (
      <section className={`${FRAME} ${FRAMES.stopped}`}>
        <AnswerHeading>
          <span className="flex items-center gap-2 text-warning">
            <IconAlertTriangle className="size-3.5" />
            No answer
          </span>
        </AnswerHeading>
        <p className="mt-3 text-sm text-fg-body">{investigation.stoppedBecause ?? "Stopped without an answer."}</p>
      </section>
    )
  }

  const verdicts = Object.entries(finding.verdicts)

  return (
    <section className={`${FRAME} ${FRAMES.answered}`}>
      <AnswerHeading>
        <span className="flex items-center gap-2 text-success">
          <IconCircleCheck className="size-3.5" />
          Answer
        </span>
      </AnswerHeading>
      <p className="mt-3 text-base leading-relaxed text-fg-primary text-pretty">{finding.summary}</p>
      {finding.suggestsIncident && !investigation.incidentId && onDeclare && (
        <div className="mt-4 flex flex-wrap items-center justify-between gap-3 edge-bar rounded-lg bg-error-tint px-4 py-3 [--edge-bar-inset:8px] [--edge-bar:var(--error)]">
          <span className="flex items-center gap-2 text-sm text-fg-primary">
            <IconAlertTriangle className="size-4 shrink-0 text-error" />
            Halon thinks this is hurting users now.
          </span>
          <IncidentsBlocked reason={declareBlockedReason}>
            <Button size="sm" onClick={onDeclare} disabled={Boolean(declareBlockedReason)}>
              Declare incident
            </Button>
          </IncidentsBlocked>
        </div>
      )}

      <div className="mt-5 flex flex-col gap-4 border-t border-border pt-5">
        {finding.cause && <AnswerPart label="Cause">{finding.cause}</AnswerPart>}
        {finding.evidence.length > 0 && (
          <AnswerPart label="Why it thinks so">
            <ul className="flex flex-col gap-2.5">
              {finding.evidence.map((item) => (
                <li key={item.id} className="flex flex-col gap-1">
                  <span>{item.claim}</span>
                  <StepLinks steps={item.steps} />
                </li>
              ))}
            </ul>
          </AnswerPart>
        )}
        {finding.fix && (
          <AnswerPart label="How to fix it">
            <FixPlan investigationId={investigation.id} fix={finding.fix} />
          </AnswerPart>
        )}
        {finding.fix?.undo && (
          <AnswerPart label="How to undo it">
            <FixPlan investigationId={investigation.id} fix={finding.fix.undo} />
          </AnswerPart>
        )}
        {finding.gaps && (
          <AnswerPart label="Could not check">
            <span className="text-fg-secondary">{finding.gaps}</span>
          </AnswerPart>
        )}
        {(finding.outcome || verdicts.length > 0) && (
          <AnswerPart label="The team says">
            <span className="text-fg-secondary">
              {finding.outcome
                ? labelFor(OUTCOME_LABELS, finding.outcome)
                : verdicts.map(([outcome, count]) => `${count} ${labelFor(OUTCOME_LABELS, outcome)?.toLowerCase()}`).join(", ")}
            </span>
          </AnswerPart>
        )}
        <AnswerPart label="Was it right?">
          <RateAnswer investigationId={investigation.id} mine={finding.myVerdict} />
        </AnswerPart>
      </div>
    </section>
  )
}
