import {
  IconArrowsMinimize,
  IconBulb,
  IconCircleCheck,
  IconCircleX,
  IconLoader2,
  IconMessageQuestion,
  IconMessagePlus,
} from "@tabler/icons-react"

import { HYPOTHESIS_STATUS, INVESTIGATION_STEP_STATUS, STEP_OUTCOME_KINDS } from "@/lib/generated/constants"
import { outcomeLabel } from "@/lib/step-outcome"
import { MetricChart } from "@/components/charts/metric-chart"
import { formatSeconds } from "@/components/investigations/format"
import { SETTLED_LABELS, isKeyOf, labelFor } from "@/components/investigations/labels"
import { NoteFiles } from "@/components/investigations/note-files"
import { StepDetails } from "@/components/investigations/step-row"
import { StepLinks } from "@/components/investigations/step-links"
import { StoryEndRow } from "@/components/investigations/story-end-row"
import { StoryIconMarker } from "@/components/investigations/story-icon-marker"
import { StoryRow } from "@/components/investigations/story-row"
import type { StoryEntry } from "@/components/investigations/story"
import { HYPOTHESIS_TONES, STEP_TONES, type Tone } from "@/components/investigations/tone"
import type { InvestigationDetail, InvestigationHypothesis, InvestigationStep } from "@/types/serializers"

// How the step went decides its colour. A call whose provider answered with an error is red even when the step ran, and
// one whose provider found nothing stays neutral.
function stepTone(step: InvestigationStep): Tone {
  if (step.outcome?.kind === STEP_OUTCOME_KINDS.FAILED) {
    return "error"
  }
  if (step.outcome?.kind === STEP_OUTCOME_KINDS.NOT_FOUND || step.outcome?.kind === STEP_OUTCOME_KINDS.REFUSED) {
    return "neutral"
  }
  return isKeyOf(STEP_TONES, step.status) ? STEP_TONES[step.status] : "neutral"
}

function hypothesisTone(hypothesis: InvestigationHypothesis): Tone {
  return isKeyOf(HYPOTHESIS_TONES, hypothesis.status) ? HYPOTHESIS_TONES[hypothesis.status] : "neutral"
}

// One entry of the run's story, drawn by its kind.
export function StoryEntryRow({ entry, investigation, connected }: { entry: StoryEntry; investigation: InvestigationDetail; connected: boolean }) {
  switch (entry.kind) {
    case "asked": {
      const who = investigation.asker?.name ?? "Someone"
      return (
        <StoryRow
          marker={<StoryIconMarker icon={IconMessageQuestion} />}
          tone="brand"
          title={
            <>
              <span className="font-medium text-fg-primary">{who}</span>
              <span className="text-fg-secondary">{investigation.question ? "asked" : "asked for an investigation"}</span>
            </>
          }
          at={investigation.createdAt}
          connected={connected}
        >
          {investigation.question && <p className="text-sm leading-relaxed text-fg-body">{investigation.question}</p>}
        </StoryRow>
      )
    }
    case "step": {
      const { step } = entry
      const tone = stepTone(step)
      const stepCharts = investigation.charts.filter((chart) => chart.stepPosition === step.position)
      return (
        <StoryRow
          id={`step-${step.position}`}
          marker={step.status === INVESTIGATION_STEP_STATUS.RUNNING ? <IconLoader2 className="size-3.5 motion-safe:animate-spin" /> : <span className="font-mono text-[11px] tabular-nums">{step.position}</span>}
          tone={tone}
          title={<span className="font-medium text-fg-primary">{step.label}</span>}
          aside={
            <>
              {step.outcome && step.outcome.kind !== STEP_OUTCOME_KINDS.ANSWERED && (
                <span className={step.outcome.kind === STEP_OUTCOME_KINDS.FAILED ? "text-error" : "text-fg-secondary"}>{outcomeLabel(step.outcome)}</span>
              )}
              {step.seconds != null && <span>{formatSeconds(step.seconds)}</span>}
            </>
          }
          at={step.startedAt}
          connected={connected}
        >
          <StepDetails step={step} />
          {stepCharts.map((chart) => (
            <div key={chart.id} className="mt-3 rounded-lg border border-border bg-surface-card px-3 py-2.5">
              <MetricChart chart={chart} />
            </div>
          ))}
        </StoryRow>
      )
    }
    case "theory":
      return (
        <StoryRow
          marker={<StoryIconMarker icon={IconBulb} />}
          tone="open"
          title={<span className="text-fg-secondary">New theory</span>}
          at={entry.hypothesis.createdAt}
          connected={connected}
        >
          <p className="text-sm leading-relaxed text-fg-body">{entry.hypothesis.assertion}</p>
        </StoryRow>
      )
    case "settled": {
      const { hypothesis } = entry
      const confirmed = hypothesis.status === HYPOTHESIS_STATUS.SUPPORTED
      return (
        <StoryRow
          marker={<StoryIconMarker icon={confirmed ? IconCircleCheck : IconCircleX} />}
          tone={hypothesisTone(hypothesis)}
          title={<span className="font-medium text-fg-primary">{labelFor(SETTLED_LABELS, hypothesis.status)}</span>}
          connected={connected}
        >
          <div className="flex flex-col gap-1.5">
            <p className={`text-sm leading-relaxed ${confirmed ? "text-fg-body" : "text-fg-muted"}`}>{hypothesis.assertion}</p>
            <StepLinks steps={hypothesis.steps} />
          </div>
        </StoryRow>
      )
    }
    case "note": {
      const { note } = entry
      return (
        <StoryRow
          marker={<StoryIconMarker icon={IconMessagePlus} />}
          tone="brand"
          title={
            <>
              <span className="font-medium text-fg-primary">{note.author?.name ?? "A responder"}</span>
              <span className="text-fg-secondary">{note.takenAt ? "added" : "added, waiting for the next step"}</span>
            </>
          }
          at={note.createdAt}
          connected={connected}
        >
          <div className="flex flex-col gap-1.5">
            {note.content && <p className="text-sm leading-relaxed text-fg-body">{note.content}</p>}
            <NoteFiles files={note.files} />
          </div>
        </StoryRow>
      )
    }
    case "room":
      return (
        <StoryRow
          marker={<StoryIconMarker icon={IconArrowsMinimize} />}
          tone="neutral"
          title={<span className="text-fg-muted">{entry.compaction.title}</span>}
          at={entry.compaction.at}
          connected={connected}
        />
      )
    case "end":
      return <StoryEndRow investigation={investigation} />
  }
}
