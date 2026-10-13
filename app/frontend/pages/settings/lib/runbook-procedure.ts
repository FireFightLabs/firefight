import { WATCH_SPEC_KEYS } from "@/lib/generated/constants"
import { isObject, written, type JsonObject } from "@/lib/tool-fields"
import { sentWatch, watchState, type WatchState } from "@/lib/watch-spec"
import type { RunbookSettings } from "@/types/serializers"

export interface EditableInput {
  key: string
  name: string
  question: string
  defaultValue: string
}

export interface ProcedureState {
  aliasesText: string
  inputs: EditableInput[]
  watch: WatchState
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
  const steps = watch[WATCH_SPEC_KEYS.STEPS]
  const labels = (Array.isArray(steps) ? steps : []).flatMap((step: unknown) => {
    const label = isObject(step) ? step[WATCH_SPEC_KEYS.LABEL] : undefined
    return typeof label === "string" ? [ label ] : []
  })
  const title = typeof watch[WATCH_SPEC_KEYS.TITLE] === "string" ? String(watch[WATCH_SPEC_KEYS.TITLE]) : ""
  return [ title, labels.join(", ") ].filter((part) => part.length > 0).join(": ")
}

// A step Halon runs, as its tool's name with the arguments below it.
export function stepCall(tool: string, args: Record<string, unknown>): string {
  const lines = Object.entries(args).map(([ key, value ]) => `${key}: ${written(value)}`)
  return [ tool, ...lines ].join("\n")
}
