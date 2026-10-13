import type { FormDataConvertible } from "@inertiajs/core"

import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"

// What JSON gives back for an object, which is also what a form request can carry.
export type JsonObject = { [key: string]: FormDataConvertible }

type FieldKind = (typeof RUNBOOK_FIELD_KINDS)[keyof typeof RUNBOOK_FIELD_KINDS]

// One field of a form made from a tool's parameters, as the server describes it (ToolField on the Ruby side).
export interface ToolField {
  key: string
  kind: FieldKind
  options: string[]
  required: boolean
  description: string | null
  // Another field and the values it must hold for this one to be asked.
  shown_when?: Record<string, string[]> | null
}

// A value as it stands in the form: what is kept, and the words typed into a number or list field while they are typed.
// A key the person never touched keeps exactly what was saved, so what Halon saved comes back out unchanged.
export interface ArgumentsState {
  values: JsonObject
  drafts: Record<string, string>
}

// A runbook's input standing in for a value, such as {{count}}.
export const PLACEHOLDER = /^\s*\{\{\s*[a-z0-9_]+\s*\}\}\s*$/
// A workflow's reference standing in for a value, such as {{steps.check.count}}.
export const REFERENCE = /^\s*\{\{\s*[a-z][a-z0-9_]*(\.[A-Za-z0-9_-]+)*\s*\}\}\s*$/
export const NUMBER = /^\s*-?\d+(\.\d+)?\s*$/
export const NOT_A_NUMBER = "A number, or an input such as {{count}}."
export const REQUIRED = "Required."

export function isObject(value: unknown): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

type JsonValue = FormDataConvertible

// A value read from JSON as one a request can carry again, anything that is not plain JSON left out.
export function jsonValue(value: unknown): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
    return value
  }
  if (Array.isArray(value)) {
    return value.map(jsonValue)
  }
  if (typeof value === "object") {
    return jsonObject(value as Record<string, unknown>)
  }
  return null
}

export function jsonObject(value: Record<string, unknown> | null | undefined): JsonObject {
  return Object.fromEntries(Object.entries(value ?? {}).map(([ key, inner ]) => [ key, jsonValue(inner) ]))
}

export function emptyArguments(): ArgumentsState {
  return { values: {}, drafts: {} }
}

export function argumentsState(saved: Record<string, unknown> | null | undefined): ArgumentsState {
  return { values: isObject(saved) ? { ...saved } : {}, drafts: {} }
}

// Whether a field is asked, given what the fields it depends on hold.
export function isShown(field: ToolField, state: ArgumentsState): boolean {
  if (!field.shown_when) {
    return true
  }
  return Object.entries(field.shown_when).every(([ key, values ]) => values.includes(String(state.values[key] ?? "")))
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
export function withField(state: ArgumentsState, field: ToolField, entered: string | boolean, placeholder: RegExp = PLACEHOLDER): ArgumentsState {
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
    values[field.key] = placeholder.test(entered) || !NUMBER.test(entered) ? entered.trim() : Number(entered)
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
export function fieldErrors(fields: ToolField[], state: ArgumentsState, placeholder: RegExp = PLACEHOLDER): Record<string, string> {
  const errors: Record<string, string> = {}
  fields.filter((field) => isShown(field, state)).forEach((field) => {
    const value = state.values[field.key]
    if (field.required && field.kind !== RUNBOOK_FIELD_KINDS.KEPT && (value === undefined || value === "")) {
      errors[field.key] = REQUIRED
    }
    if (field.kind === RUNBOOK_FIELD_KINDS.NUMBER && typeof value === "string" && !placeholder.test(value)) {
      errors[field.key] = NOT_A_NUMBER
    }
  })
  return errors
}

// Saved arguments the fields do not hold, such as one Halon added or a shape a form cannot show. They are kept.
export function otherArguments(fields: ToolField[] | null, state: ArgumentsState): [string, unknown][] {
  const shown = new Set((fields ?? []).filter((field) => field.kind !== RUNBOOK_FIELD_KINDS.KEPT).map((field) => field.key))
  return Object.entries(state.values).filter(([ key ]) => !shown.has(key))
}

export function written(value: unknown): string {
  return typeof value === "string" ? value : JSON.stringify(value)
}
