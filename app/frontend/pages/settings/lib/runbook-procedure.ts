import type { FormDataConvertible } from "@inertiajs/core"

import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"
import type { RunbookSettings, RunbookToolChoice, RunbookWatchRead } from "@/types/serializers"

// What JSON gives back for an object, which is also what a form request can carry.
export type JsonObject = { [key: string]: FormDataConvertible }

export type ToolField = RunbookToolChoice["fields"][number]

// A value as it stands in the form: what is kept, and the words typed into a number or list field while they are typed.
// A key the person never touched keeps exactly what was saved, so a runbook Halon saved comes back out unchanged.
export interface ArgumentsState {
  values: JsonObject
  drafts: Record<string, string>
}

export interface EditableInput {
  key: string
  name: string
  question: string
  defaultValue: string
}

export interface WatchState {
  on: boolean
  // What was saved, with every edit made on top of it, so anything the editor does not show is kept.
  spec: JsonObject
  steps: { key: string; spec: JsonObject }[]
  minutesDraft: string
}

export interface ProcedureState {
  aliasesText: string
  inputs: EditableInput[]
  watch: WatchState
}

const PLACEHOLDER = /^\s*\{\{\s*[a-z0-9_]+\s*\}\}\s*$/
const NUMBER = /^\s*-?\d+(\.\d+)?\s*$/
export const NOT_A_NUMBER = "A number, or an input such as {{count}}."
export const REQUIRED = "Required."
const WATCH_STEP_REQUIRED = "Name what to watch and on which resource."
const WATCH_DONE_REQUIRED = "Say what counts as done, failed, or the goal."
const WATCH_NO_STEPS = "Add at least one thing to watch, or turn the watch off."

export function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

export function emptyArguments(): ArgumentsState {
  return { values: {}, drafts: {} }
}

export function argumentsState(saved: Record<string, unknown> | null | undefined): ArgumentsState {
  return { values: isObject(saved) ? { ...saved } : {}, drafts: {} }
}

// How a saved value reads in its field.
export function shownValue(field: ToolField, state: ArgumentsState): string {
  const draft = state.drafts[field.key]
  if (draft !== undefined) {
    return draft
  }
  const value = state.values[field.key]
  if (value === undefined || value === null) {
    return ""
  }
  return Array.isArray(value) ? value.map(String).join(", ") : String(value)
}

// The state with one field set from what was typed or chosen. An empty field is left out rather than sent empty.
export function withField(state: ArgumentsState, field: ToolField, entered: string | boolean): ArgumentsState {
  const values = { ...state.values }
  const drafts = { ...state.drafts }
  delete drafts[field.key]
  if (typeof entered === "boolean") {
    values[field.key] = entered
    return { values, drafts }
  }
  if (entered.trim().length === 0) {
    delete values[field.key]
    return { values, drafts }
  }
  if (field.kind === RUNBOOK_FIELD_KINDS.NUMBER) {
    drafts[field.key] = entered
    values[field.key] = PLACEHOLDER.test(entered) || !NUMBER.test(entered) ? entered.trim() : Number(entered)
    return { values, drafts }
  }
  if (field.kind === RUNBOOK_FIELD_KINDS.LIST) {
    drafts[field.key] = entered
    values[field.key] = entered.split(",").map((part) => part.trim()).filter((part) => part.length > 0)
    return { values, drafts }
  }
  values[field.key] = entered
  return { values, drafts }
}

export function withoutArgument(state: ArgumentsState, key: string): ArgumentsState {
  const values = { ...state.values }
  const drafts = { ...state.drafts }
  delete values[key]
  delete drafts[key]
  return { values, drafts }
}

// What is wrong with each field, by its key: a required one left empty, or a number that is not one.
export function fieldErrors(fields: ToolField[], state: ArgumentsState): Record<string, string> {
  const errors: Record<string, string> = {}
  fields.forEach((field) => {
    const value = state.values[field.key]
    if (field.required && field.kind !== RUNBOOK_FIELD_KINDS.KEPT && (value === undefined || value === "")) {
      errors[field.key] = REQUIRED
    }
    if (field.kind === RUNBOOK_FIELD_KINDS.NUMBER && typeof value === "string" && !PLACEHOLDER.test(value)) {
      errors[field.key] = NOT_A_NUMBER
    }
  })
  return errors
}

// Saved arguments the tool's fields do not hold, such as one Halon added or a shape a form cannot show. They are kept.
export function otherArguments(fields: ToolField[] | null, state: ArgumentsState): [string, unknown][] {
  const shown = new Set((fields ?? []).filter((field) => field.kind !== RUNBOOK_FIELD_KINDS.KEPT).map((field) => field.key))
  return Object.entries(state.values).filter(([ key ]) => !shown.has(key))
}

export function written(value: unknown): string {
  return typeof value === "string" ? value : JSON.stringify(value)
}

function watchSteps(spec: JsonObject): { key: string; spec: JsonObject }[] {
  const steps = Array.isArray(spec.steps) ? spec.steps : []
  return steps.filter(isObject).map((step) => ({ key: crypto.randomUUID(), spec: { ...step } }))
}

export function watchState(saved: Record<string, unknown> | null | undefined): WatchState {
  const spec: JsonObject = isObject(saved) ? { ...saved } : {}
  const minutes = spec.minutes
  return {
    on: isObject(saved),
    spec,
    steps: watchSteps(spec),
    minutesDraft: minutes === undefined || minutes === null ? "" : String(minutes),
  }
}

export function procedureState(runbook: RunbookSettings | null | undefined): ProcedureState {
  return {
    aliasesText: (runbook?.aliases ?? []).join(", "),
    inputs: (runbook?.inputs ?? []).map((input) => ({
      key: crypto.randomUUID(),
      name: input.key,
      question: input.question,
      defaultValue: input.default ?? "",
    })),
    watch: watchState(runbook?.watch),
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

export function isHistoryRead(spec: JsonObject, reads: RunbookWatchRead[]): boolean {
  return reads.some((read) => read.history && read.name === spec.capability)
}

// What is wrong with the watch, as one sentence for the section and one per step by its key.
export function watchErrors(watch: WatchState, reads: RunbookWatchRead[]): { watch: string | null; steps: Record<string, string> } {
  const steps: Record<string, string> = {}
  if (!watch.on) {
    return { watch: null, steps }
  }
  watch.steps.forEach((step) => {
    if (!stepText(step.spec, "label") || !stepText(step.spec, "capability") || !stepText(step.spec, "resource")) {
      steps[step.key] = WATCH_STEP_REQUIRED
      return
    }
    const decided = [ "done_when", "failed_when", "goal" ].some((key) => stepText(step.spec, key).length > 0)
    if (!isHistoryRead(step.spec, reads) && !decided) {
      steps[step.key] = WATCH_DONE_REQUIRED
    }
  })
  const minutes = watch.minutesDraft.trim()
  const badMinutes = minutes.length > 0 && !NUMBER.test(minutes) && !PLACEHOLDER.test(minutes)
  const sectionError = watch.steps.length === 0 ? WATCH_NO_STEPS : badMinutes ? NOT_A_NUMBER : null
  return { watch: sectionError, steps }
}

function sentWatch(watch: WatchState): JsonObject | null {
  if (!watch.on) {
    return null
  }
  const spec: JsonObject = { ...watch.spec, steps: watch.steps.map((step) => step.spec) }
  const minutes = watch.minutesDraft.trim()
  if (minutes.length === 0) {
    delete spec.minutes
  } else {
    spec.minutes = NUMBER.test(minutes) ? Number(minutes) : minutes
  }
  return spec
}

export interface SentStep {
  id?: string
  title: string
  instruction: string
  tool: string | null
  arguments: JsonObject
}

export interface ProcedurePayload {
  inputs: { key: string; question: string; default: string }[]
  aliases: string[]
  watch: JsonObject | null
}

export function procedurePayload(state: ProcedureState): ProcedurePayload {
  return {
    inputs: state.inputs.map(sentInput),
    aliases: state.aliasesText.split(",").map((name) => name.trim()).filter((name) => name.length > 0),
    watch: sentWatch(state.watch),
  }
}

function sentInput(input: EditableInput) {
  return { key: input.name.trim(), question: input.question.trim(), default: input.defaultValue.trim() }
}

// The inputs a field can take instead of a fixed value, written as Halon reads them.
export function inputPlaceholders(inputs: EditableInput[]): { value: string; label: string }[] {
  return inputs.filter((input) => input.name.trim().length > 0).map((input) => ({
    value: `{{${input.name.trim()}}}`,
    label: `Asked each time: ${input.question.trim() || input.name.trim()}`,
  }))
}

// What a watch follows, as a person reads it: its title, then the label of each thing it checks.
export function watchedSummary(watch: Record<string, unknown>): string {
  const steps = Array.isArray(watch.steps) ? watch.steps : []
  const labels = steps.flatMap((step: unknown) => (isObject(step) && typeof step.label === "string" ? [ step.label ] : []))
  const title = typeof watch.title === "string" ? watch.title : ""
  return [ title, labels.join(", ") ].filter((part) => part.length > 0).join(": ")
}

// A step Halon runs, as its tool's name with the arguments below it.
export function stepCall(tool: string, args: Record<string, unknown>): string {
  const lines = Object.entries(args).map(([ key, value ]) => `${key}: ${written(value)}`)
  return [ tool, ...lines ].join("\n")
}
