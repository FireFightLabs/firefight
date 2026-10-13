import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import {
  NOT_A_NUMBER,
  NUMBER,
  PLACEHOLDER,
  argumentsState,
  emptyArguments,
  isObject,
  type ArgumentsState,
  type JsonObject,
} from "@/lib/tool-fields"
import type { RunbookWatchRead, WorkflowToolChoice } from "@/types/serializers"

// A watch's spec as its editor holds it, the same wherever a watch is written: a runbook's watch afterwards, or a
// workflow's Watch step. Anything saved that the editor does not show is kept.

// A read tool a watch can follow, with the fields a watch asks of it when they differ from a call's.
export interface WatchTool {
  name: string
  group: string
  description: string
  reads: boolean
  fields: WorkflowToolChoice["fields"]
  watchFields: WorkflowToolChoice["fields"] | null
}

// One thing a watch follows. args holds a read tool's arguments as they are typed, sent as the step's arguments.
// waitsFor holds the keys of the earlier steps it waits for, so renaming or removing one keeps the rest right, and
// keptWaits what was saved that names no step here, sent back as it was.
export interface WatchStepState {
  key: string
  spec: JsonObject
  args: ArgumentsState
  waitsFor: string[]
  keptWaits: string[]
}

export interface WatchState {
  // Whether there is a watch at all. A workflow's Watch step always has one.
  on: boolean
  // What was saved, with every edit made on top of it, so anything the editor does not show is kept.
  spec: JsonObject
  steps: WatchStepState[]
  minutesDraft: string
}


export const WATCH_NO_STEPS = "Add at least one thing to watch, or turn the watch off."

function watchSteps(spec: JsonObject): WatchStepState[] {
  const steps = spec[WATCH_SPEC_KEYS.STEPS]
  const loaded = (Array.isArray(steps) ? steps : []).filter(isObject).map((step) => {
    const saved = step[WATCH_SPEC_KEYS.ARGUMENTS]
    return { key: crypto.randomUUID(), spec: { ...step }, args: argumentsState(isObject(saved) ? saved : null), waitsFor: [], keptWaits: [] }
  })
  return loaded.map((step, index) => withSavedWaits(step, loaded.slice(0, index)))
}

// The saved steps it waits for, each by its name or its number counting from 1, among the steps before it.
function withSavedWaits(step: WatchStepState, earlier: WatchStepState[]): WatchStepState {
  const saved = step.spec[WATCH_SPEC_KEYS.WAITS_FOR]
  const refs = (Array.isArray(saved) ? saved : []).map(String)
  const waitsFor: string[] = []
  const keptWaits: string[] = []
  refs.forEach((ref) => {
    const found = earlier.find((each, index) => stepText(each.spec, WATCH_SPEC_KEYS.LABEL).trim().toLowerCase() === ref.trim().toLowerCase() || String(index + 1) === ref.trim())
    if (found) {
      waitsFor.push(found.key)
    } else {
      keptWaits.push(ref)
    }
  })
  return { ...step, waitsFor, keptWaits }
}

// A new thing to follow, reading the first read on the map when there is one.
export function firstWatchStep(reads: RunbookWatchRead[] | null): WatchStepState {
  const first = reads?.[0]?.name
  return newWatchStep(first ? { [WATCH_SPEC_KEYS.CAPABILITY]: first } : {})
}

export function newWatchStep(spec: JsonObject): WatchStepState {
  return { key: crypto.randomUUID(), spec, args: emptyArguments(), waitsFor: [], keptWaits: [] }
}

// How an earlier step is named where another waits for it: its name, or its number when it has none.
export function waitsName(step: WatchStepState, index: number): string {
  return stepText(step.spec, WATCH_SPEC_KEYS.LABEL).trim() || String(index + 1)
}

// A step picks what it reads with: a capability on a resource, or a read tool with its arguments. Choosing one clears
// what only the other takes.
export function withRead(step: WatchStepState, name: string, capability: boolean): WatchStepState {
  const spec = { ...step.spec }
  if (capability) {
    delete spec[WATCH_SPEC_KEYS.TOOL]
    delete spec[WATCH_SPEC_KEYS.FOCUS]
    delete spec[WATCH_SPEC_KEYS.ARGUMENTS]
    spec[WATCH_SPEC_KEYS.CAPABILITY] = name
    return { ...step, spec, args: emptyArguments() }
  }
  delete spec[WATCH_SPEC_KEYS.CAPABILITY]
  delete spec[WATCH_SPEC_KEYS.RESOURCE]
  delete spec[WATCH_SPEC_KEYS.NAME]
  delete spec[WATCH_SPEC_KEYS.RUN]
  delete spec[WATCH_SPEC_KEYS.REPORT_START]
  spec[WATCH_SPEC_KEYS.TOOL] = name
  return { ...step, spec, args: spec[WATCH_SPEC_KEYS.TOOL] === step.spec[WATCH_SPEC_KEYS.TOOL] ? step.args : emptyArguments() }
}

// What the step reads with, a read tool's name or a capability's.
export function readOf(spec: JsonObject): string {
  return stepText(spec, WATCH_SPEC_KEYS.TOOL) || stepText(spec, WATCH_SPEC_KEYS.CAPABILITY)
}

// A step waits for earlier steps by their names, or their numbers when they have none, worked out as it is sent.
function sentStep(step: WatchStepState, earlier: WatchStepState[]): JsonObject {
  const spec = { ...step.spec }
  const waits = [
    ...earlier.flatMap((each, index) => (step.waitsFor.includes(each.key) ? [ waitsName(each, index) ] : [])),
    ...step.keptWaits,
  ]
  if (waits.length > 0) {
    spec[WATCH_SPEC_KEYS.WAITS_FOR] = waits
  } else {
    delete spec[WATCH_SPEC_KEYS.WAITS_FOR]
  }
  if (!stepText(step.spec, WATCH_SPEC_KEYS.TOOL)) {
    return spec
  }
  return { ...spec, [WATCH_SPEC_KEYS.ARGUMENTS]: step.args.values }
}

export function watchState(saved: Record<string, unknown> | null | undefined): WatchState {
  const spec: JsonObject = isObject(saved) ? { ...saved } : {}
  const minutes = spec[WATCH_SPEC_KEYS.MINUTES]
  return {
    on: isObject(saved),
    spec,
    steps: watchSteps(spec),
    minutesDraft: minutes === undefined || minutes === null ? "" : String(minutes),
  }
}

export function stepText(spec: JsonObject, key: string): string {
  const value = spec[key]
  return value === undefined || value === null ? "" : String(value)
}

// One field of a watch's step set from what was typed. An empty one is left out.
export function withStepField(spec: JsonObject, key: string, entered: string | boolean): JsonObject {
  const next = { ...spec }
  if (typeof entered === "string" && entered.trim().length === 0) {
    delete next[key]
    return next
  }
  next[key] = entered
  return next
}

// The new deploy a step waits for, or null when it waits for none. An empty one waits for any newer deploy.
export function newDeployOf(spec: JsonObject): JsonObject | null {
  const asked = spec[WATCH_SPEC_KEYS.NEW_DEPLOY]
  return isObject(asked) ? asked : null
}

// Turns waiting for a new deploy on, for any newer one, or off.
export function withNewDeploy(spec: JsonObject, on: boolean): JsonObject {
  const next = { ...spec }
  if (on) {
    next[WATCH_SPEC_KEYS.NEW_DEPLOY] = newDeployOf(spec) ?? {}
  } else {
    delete next[WATCH_SPEC_KEYS.NEW_DEPLOY]
  }
  return next
}

// One field of the new deploy a step waits for, such as its commit. An empty one is left out.
export function withNewDeployField(spec: JsonObject, key: string, entered: string): JsonObject {
  return { ...spec, [WATCH_SPEC_KEYS.NEW_DEPLOY]: withStepField(newDeployOf(spec) ?? {}, key, entered) }
}

export function isHistoryRead(spec: JsonObject, reads: RunbookWatchRead[]): boolean {
  return reads.some((read) => read.history && read.name === spec[WATCH_SPEC_KEYS.CAPABILITY])
}

// What is wrong with the watch before it is sent, as one sentence for the section. What each item must name to be
// followed is checked by the server when it saves (Runbook::Procedure), and an item's name is optional.
export function watchError(watch: WatchState, noSteps: string = WATCH_NO_STEPS): string | null {
  if (!watch.on) {
    return null
  }
  const minutes = watch.minutesDraft.trim()
  const badMinutes = minutes.length > 0 && !NUMBER.test(minutes) && !PLACEHOLDER.test(minutes)
  return watch.steps.length === 0 ? noSteps : badMinutes ? NOT_A_NUMBER : null
}

export function sentWatch(watch: WatchState): JsonObject | null {
  if (!watch.on) {
    return null
  }
  const spec: JsonObject = { ...watch.spec, [WATCH_SPEC_KEYS.STEPS]: watch.steps.map((step, index) => sentStep(step, watch.steps.slice(0, index))) }
  const minutes = watch.minutesDraft.trim()
  if (minutes.length === 0) {
    delete spec[WATCH_SPEC_KEYS.MINUTES]
  } else {
    spec[WATCH_SPEC_KEYS.MINUTES] = NUMBER.test(minutes) ? Number(minutes) : minutes
  }
  return spec
}

