import type { InvestigationDetail, InvestigationHypothesis, InvestigationStep } from "@/types/serializers"

export type StoryEntry =
  | { kind: "asked"; key: string }
  | { kind: "step"; key: string; step: InvestigationStep }
  | { kind: "theory"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "settled"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "end"; key: string }

function beforeStep(hypothesis: InvestigationHypothesis, step: InvestigationStep): boolean {
  return step.startedAt != null && hypothesis.createdAt <= step.startedAt
}

// The run in the order it happened. A theory appears where it was first written down, and again as settled right
// after the last step it rests on, so a reader sees what each step was for and what it decided.
export function buildStory(investigation: InvestigationDetail): StoryEntry[] {
  const steps = [...investigation.steps].sort((first, second) => first.position - second.position)
  const unplaced = [...investigation.hypotheses].sort((first, second) => first.createdAt.localeCompare(second.createdAt))
  const story: StoryEntry[] = [{ kind: "asked", key: "asked" }]

  function placeTheoriesBefore(step: InvestigationStep | null) {
    while (unplaced.length > 0 && (step == null || beforeStep(unplaced[0], step))) {
      const hypothesis = unplaced.shift()
      if (hypothesis) {
        story.push({ kind: "theory", key: `theory-${hypothesis.id}`, hypothesis })
      }
    }
  }

  // A theory written down only once it was settled is told once, as settled.
  function settle(hypothesis: InvestigationHypothesis) {
    const waiting = unplaced.indexOf(hypothesis)
    if (waiting >= 0) {
      unplaced.splice(waiting, 1)
    }
    story.push({ kind: "settled", key: `settled-${hypothesis.id}`, hypothesis })
  }

  steps.forEach((step) => {
    placeTheoriesBefore(step)
    story.push({ kind: "step", key: `step-${step.position}`, step })
    investigation.hypotheses.filter((hypothesis) => hypothesis.settledAfterStep === step.position).forEach(settle)
  })
  placeTheoriesBefore(null)

  // A theory settled with no step behind it is still settled, at the end.
  investigation.hypotheses.filter((hypothesis) => hypothesis.settled && hypothesis.settledAfterStep == null).forEach(settle)

  story.push({ kind: "end", key: "end" })
  return story
}
