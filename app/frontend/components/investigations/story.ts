import type { ChatCompaction, InvestigationDetail, InvestigationHypothesis, InvestigationNote, InvestigationStep } from "@/types/serializers"

export type StoryEntry =
  | { kind: "asked"; key: string }
  | { kind: "step"; key: string; step: InvestigationStep }
  | { kind: "theory"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "settled"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "note"; key: string; note: InvestigationNote }
  | { kind: "room"; key: string; compaction: ChatCompaction }
  | { kind: "end"; key: string }

function beforeStep(hypothesis: InvestigationHypothesis, step: InvestigationStep): boolean {
  return step.startedAt != null && hypothesis.createdAt <= step.startedAt
}

// A note is placed where the run read it, and one still waiting for the next step comes last.
function readBefore(note: InvestigationNote, step: InvestigationStep): boolean {
  return note.takenAt != null && step.startedAt != null && note.takenAt <= step.startedAt
}

// Room is made just before the model chooses its next step, so it sits ahead of every step that started after it.
function madeBefore(compaction: ChatCompaction, step: InvestigationStep): boolean {
  return step.startedAt != null && Date.parse(compaction.at) <= Date.parse(step.startedAt)
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

  const unreadNotes = [...investigation.notes]

  function placeNotesBefore(step: InvestigationStep | null) {
    while (unreadNotes.length > 0 && (step == null || readBefore(unreadNotes[0], step))) {
      const note = unreadNotes.shift()
      if (note) {
        story.push({ kind: "note", key: `note-${note.id}`, note })
      }
    }
  }

  const unplacedRoom = [...investigation.compactions].sort((first, second) => Date.parse(first.at) - Date.parse(second.at))

  function placeRoomBefore(step: InvestigationStep | null) {
    while (unplacedRoom.length > 0 && (step == null || madeBefore(unplacedRoom[0], step))) {
      const compaction = unplacedRoom.shift()
      if (compaction) {
        story.push({ kind: "room", key: compaction.key, compaction })
      }
    }
  }

  steps.forEach((step) => {
    placeRoomBefore(step)
    placeNotesBefore(step)
    placeTheoriesBefore(step)
    story.push({ kind: "step", key: `step-${step.position}`, step })
    investigation.hypotheses.filter((hypothesis) => hypothesis.settledAfterStep === step.position).forEach(settle)
  })
  placeTheoriesBefore(null)
  placeNotesBefore(null)
  placeRoomBefore(null)

  // A theory settled with no step behind it is still settled, at the end.
  investigation.hypotheses.filter((hypothesis) => hypothesis.settled && hypothesis.settledAfterStep == null).forEach(settle)

  story.push({ kind: "end", key: "end" })
  return story
}
