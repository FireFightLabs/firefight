import type {
  ChatCompaction, ChatModelSwitch, InvestigationDetail, InvestigationHelper, InvestigationHypothesis, InvestigationNote, InvestigationStep,
} from "@/types/serializers"

// One helper of a batch, with the steps it took in the order they were numbered.
export interface HelperGroup {
  helper: InvestigationHelper
  steps: InvestigationStep[]
}

export type StoryEntry =
  | { kind: "asked"; key: string }
  | { kind: "step"; key: string; step: InvestigationStep }
  | { kind: "theory"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "settled"; key: string; hypothesis: InvestigationHypothesis }
  | { kind: "note"; key: string; note: InvestigationNote }
  | { kind: "room"; key: string; compaction: ChatCompaction }
  | { kind: "helpers"; key: string; groups: HelperGroup[] }
  | { kind: "switch"; key: string; modelSwitch: ChatModelSwitch }
  | { kind: "end"; key: string }

function beforeStep(hypothesis: InvestigationHypothesis, step: InvestigationStep): boolean {
  return step.startedAt != null && hypothesis.createdAt <= step.startedAt
}

// A note is placed where the run read it, and one still waiting for the next step comes last.
function readBefore(note: InvestigationNote, step: InvestigationStep): boolean {
  return note.takenAt != null && step.startedAt != null && note.takenAt <= step.startedAt
}

type QuietLine = { kind: "room"; line: ChatCompaction } | { kind: "switch"; line: ChatModelSwitch }

// Room is made, and a backup model takes over, just before the model chooses its next step, so each sits ahead of
// every step that started after it.
function madeBefore(quiet: QuietLine, step: InvestigationStep): boolean {
  return step.startedAt != null && Date.parse(quiet.line.at) <= Date.parse(step.startedAt)
}

function storyEntryFor(quiet: QuietLine): StoryEntry {
  return quiet.kind === "room"
    ? { kind: "room", key: quiet.line.key, compaction: quiet.line }
    : { kind: "switch", key: quiet.line.key, modelSwitch: quiet.line }
}

// The run in the order it happened. A theory appears where it was first written down, and again as settled right
// after the last step it rests on, so a reader sees what each step was for and what it decided.
export function buildStory(investigation: InvestigationDetail): StoryEntry[] {
  const numbered = [...investigation.steps].sort((first, second) => first.position - second.position)
  // A helper's steps are told under its helper, so only the run's own steps keep a place of their own.
  const steps = numbered.filter((step) => step.helperId == null)
  const batches = helperBatches(investigation.helpers, numbered)
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

  const unplacedRoom: QuietLine[] = [
    ...investigation.compactions.map((line): QuietLine => ({ kind: "room", line })),
    ...investigation.modelSwitches.map((line): QuietLine => ({ kind: "switch", line })),
  ].sort((first, second) => Date.parse(first.line.at) - Date.parse(second.line.at))

  function placeRoomBefore(step: InvestigationStep | null) {
    while (unplacedRoom.length > 0 && (step == null || madeBefore(unplacedRoom[0], step))) {
      const quiet = unplacedRoom.shift()
      if (quiet) {
        story.push(storyEntryFor(quiet))
      }
    }
  }

  // Helpers handed off together are one entry, placed where they started, and a theory settled by one of their steps is
  // told right after them.
  function placeBatchesBefore(step: InvestigationStep | null) {
    while (batches.length > 0 && (step == null || startedBefore(batches[0], step))) {
      const batch = batches.shift()
      if (!batch) {
        return
      }
      const first = batch.groups.flatMap((group) => group.steps)[0]
      if (first) {
        placeRoomBefore(first)
        placeNotesBefore(first)
        placeTheoriesBefore(first)
      }
      story.push({ kind: "helpers", key: `helpers-${batch.key}`, groups: batch.groups })
      const positions = batch.groups.flatMap((group) => group.steps.map((helperStep) => helperStep.position))
      investigation.hypotheses.filter((hypothesis) => hypothesis.settledAfterStep != null && positions.includes(hypothesis.settledAfterStep)).forEach(settle)
    }
  }

  steps.forEach((step) => {
    placeBatchesBefore(step)
    placeRoomBefore(step)
    placeNotesBefore(step)
    placeTheoriesBefore(step)
    story.push({ kind: "step", key: `step-${step.position}`, step })
    investigation.hypotheses.filter((hypothesis) => hypothesis.settledAfterStep === step.position).forEach(settle)
  })
  placeBatchesBefore(null)
  placeTheoriesBefore(null)
  placeNotesBefore(null)
  placeRoomBefore(null)

  // A theory settled with no step behind it is still settled, at the end.
  investigation.hypotheses.filter((hypothesis) => hypothesis.settled && hypothesis.settledAfterStep == null).forEach(settle)

  story.push({ kind: "end", key: "end" })
  return story
}

interface HelperBatch {
  key: string
  startedAt: string
  groups: HelperGroup[]
}

function startedBefore(batch: HelperBatch, step: InvestigationStep): boolean {
  return step.startedAt != null && Date.parse(batch.startedAt) <= Date.parse(step.startedAt)
}

// The helpers one run_helpers call started, in the order they started, each with its own steps.
function helperBatches(helpers: InvestigationHelper[], steps: InvestigationStep[]): HelperBatch[] {
  const batches = new Map<string, HelperBatch>()
  helpers.forEach((helper) => {
    const batch = batches.get(helper.toolCallId) ?? { key: helper.toolCallId, startedAt: helper.startedAt, groups: [] }
    batch.groups.push({ helper, steps: steps.filter((step) => step.helperId === helper.id) })
    batches.set(helper.toolCallId, batch)
  })
  return [...batches.values()].sort((first, second) => Date.parse(first.startedAt) - Date.parse(second.startedAt))
}
