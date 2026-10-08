import type { FormDataConvertible } from "@inertiajs/core"

import type { RunbookSettings } from "@/types/serializers"
import type { EditableInput, ProcedureState } from "@/pages/settings/components/runbooks/runbook-procedure-editor"
import type { EditableStep } from "@/pages/settings/components/runbooks/runbook-steps-editor"

const NOT_AN_OBJECT = "Write this as a JSON object, such as { \"key\": \"value\" }."

// What JSON.parse gives back for an object, which is also what a form request can carry.
type JsonObject = { [key: string]: FormDataConvertible }

type Parsed = { value: JsonObject | null; error: string | null }

// An object written as JSON, nothing when the text is empty, or why it could not be read.
export function parseObject(text: string): Parsed {
  if (text.trim().length === 0) {
    return { value: null, error: null }
  }
  try {
    const value: unknown = JSON.parse(text)
    return isObject(value) ? { value, error: null } : { value: null, error: NOT_AN_OBJECT }
  } catch {
    return { value: null, error: NOT_AN_OBJECT }
  }
}

function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

export function objectText(value: Record<string, unknown> | null | undefined): string {
  if (!value || Object.keys(value).length === 0) {
    return ""
  }
  return JSON.stringify(value, null, 2)
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
    watchText: objectText(runbook?.watch),
  }
}

export interface ProcedurePayload {
  steps: { id?: string; title: string; instruction: string; tool: string | null; arguments: JsonObject }[]
  inputs: { key: string; question: string; default: string }[]
  aliases: string[]
  watch: JsonObject | null
}

export interface ProcedureErrors {
  steps: Record<string, string>
  watch: string | null
}

// What the form sends, or the JSON it could not read, by the step it belongs to.
export function procedurePayload(steps: EditableStep[], state: ProcedureState): { payload: ProcedurePayload; errors: ProcedureErrors | null } {
  const stepErrors: Record<string, string> = {}
  const sentSteps = steps.map((step) => {
    const tool = step.tool.trim()
    const parsed = tool.length > 0 ? parseObject(step.argumentsText) : { value: null, error: null }
    if (parsed.error) {
      stepErrors[step.key] = `Arguments: ${parsed.error}`
    }
    return { id: step.id, title: step.title, instruction: step.instruction, tool: tool.length > 0 ? tool : null, arguments: parsed.value ?? {} }
  })
  const watch = parseObject(state.watchText)
  const payload = {
    steps: sentSteps,
    inputs: state.inputs.map(sentInput),
    aliases: state.aliasesText.split(",").map((name) => name.trim()).filter((name) => name.length > 0),
    watch: watch.value,
  }
  const failed = Object.keys(stepErrors).length > 0 || watch.error !== null
  return { payload, errors: failed ? { steps: stepErrors, watch: watch.error } : null }
}

function sentInput(input: EditableInput) {
  return { key: input.name.trim(), question: input.question.trim(), default: input.defaultValue.trim() }
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
  const written = objectText(args)
  return written.length > 0 ? `${tool}\n${written}` : tool
}
