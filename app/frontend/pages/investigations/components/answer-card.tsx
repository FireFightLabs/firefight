import { IconLoader2 } from "@tabler/icons-react"

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { StepLinks } from "@/pages/investigations/components/step-links"
import { OUTCOME_LABELS, labelFor } from "@/pages/investigations/lib/labels"
import type { InvestigationDetail } from "@/types/serializers"

interface AnswerCardProps {
  investigation: InvestigationDetail
  live: boolean
}

// The finding once there is one, what is happening while the run works, and why it stopped otherwise.
export function AnswerCard({ investigation, live }: AnswerCardProps) {
  const finding = investigation.finding

  if (!finding) {
    return (
      <Card>
        <CardContent className="text-muted-foreground flex items-center gap-2 text-sm">
          {live && <IconLoader2 className="size-4 animate-spin" />}
          {live ? "Halon is working on it. This page updates as it goes." : (investigation.stoppedBecause ?? "Stopped without an answer.")}
        </CardContent>
      </Card>
    )
  }

  const thumbs = Object.entries(finding.verdicts)

  return (
    <Card>
      <CardHeader>
        <CardTitle>What it found</CardTitle>
        {finding.outcome && <CardDescription>The team marked this {labelFor(OUTCOME_LABELS, finding.outcome)?.toLowerCase()}.</CardDescription>}
      </CardHeader>
      <CardContent className="flex flex-col gap-5">
        <p className="leading-relaxed">{finding.summary}</p>
        {finding.cause && (
          <div className="flex flex-col gap-1">
            <h3 className="text-muted-foreground text-xs font-medium tracking-wide uppercase">Cause</h3>
            <p>{finding.cause}</p>
          </div>
        )}
        {finding.evidence.length > 0 && (
          <div className="flex flex-col gap-2">
            <h3 className="text-muted-foreground text-xs font-medium tracking-wide uppercase">Why it thinks so</h3>
            <ul className="flex flex-col gap-2">
              {finding.evidence.map((item) => (
                <li key={item.id} className="flex flex-col gap-1">
                  <span>{item.claim}</span>
                  <StepLinks steps={item.steps} />
                </li>
              ))}
            </ul>
          </div>
        )}
        {finding.gaps && (
          <div className="flex flex-col gap-1">
            <h3 className="text-muted-foreground text-xs font-medium tracking-wide uppercase">What it could not check</h3>
            <p className="text-muted-foreground">{finding.gaps}</p>
          </div>
        )}
        {thumbs.length > 0 && (
          <p className="text-muted-foreground text-sm">
            {thumbs.map(([outcome, count]) => `${count} said ${labelFor(OUTCOME_LABELS, outcome)?.toLowerCase()}`).join(", ")}
          </p>
        )}
      </CardContent>
    </Card>
  )
}
