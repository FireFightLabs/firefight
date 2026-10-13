import { IconPlus, IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { BadgeMultiSelect } from "@/components/badge-multi-select"
import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import {
  ALERT_CONDITION_OPERATOR,
  TRIGGER_NUMBER_OPERATOR,
  TRIGGER_NUMBER_OPERATORS,
  type TriggerNumberOperator,
  WORKFLOW_CONDITION_LIMIT,
} from "@/lib/generated/constants"
import { OPERATOR_LABELS } from "@/pages/halon/lib/workflow/labels"
import { CONDITION_OPERATORS, type ConditionOperator as WordOperator } from "@/pages/settings/lib/alerts"
import type { WorkflowTriggerKind } from "@/types/serializers"

export type ConditionField = WorkflowTriggerKind["conditions"][number]

// One condition as the settings hold it while it is edited: a field, how it is compared, and what with.
export interface ConditionDraft {
  key: string
  field: string
  operator: ConditionOperator
  values: string[]
  text: string
}

// A trigger's condition compares words as a routing rule's does, and a number field also as a number.
export type ConditionOperator = WordOperator | TriggerNumberOperator

const ONE_OF: ConditionOperator = ALERT_CONDITION_OPERATOR.IS_ONE_OF
const EMPTY: ConditionOperator = ALERT_CONDITION_OPERATOR.IS_EMPTY
const NUMBER_OPERATORS = TRIGGER_NUMBER_OPERATORS.map((value) => ({ value, label: OPERATOR_LABELS[value] }))
// A number field is compared as a number, picked from a list, or found empty. Comparing its words is never offered.
const NUMBER_FIELD_OPERATORS = [ ...NUMBER_OPERATORS, ...CONDITION_OPERATORS.filter((operator) => operator.value === ONE_OF || operator.value === EMPTY) ]
const NUMBER = /^-?\d+(\.\d+)?$/

function isOperator(value: unknown): value is ConditionOperator {
  return [ ...CONDITION_OPERATORS, ...NUMBER_OPERATORS ].some((operator) => operator.value === value)
}

function comparesNumbers(operator: ConditionOperator): boolean {
  return (TRIGGER_NUMBER_OPERATORS as readonly string[]).includes(operator)
}

// The comparisons a field offers, as a number for a number field and as words otherwise.
function operatorsFor(field: ConditionField | undefined) {
  return field?.number ? NUMBER_FIELD_OPERATORS : CONDITION_OPERATORS
}

// The trigger's stored conditions as drafts, each with a key of its own for React.
export function conditionDrafts(stored: unknown): ConditionDraft[] {
  if (!Array.isArray(stored)) {
    return []
  }
  return stored.flatMap((condition) => {
    if (condition === null || typeof condition !== "object") {
      return []
    }
    const entry = condition as Record<string, unknown>
    const operator = isOperator(entry.operator) ? entry.operator : ONE_OF
    const value = entry.value
    return [ {
      key: crypto.randomUUID(),
      field: typeof entry.field === "string" ? entry.field : "",
      operator,
      values: Array.isArray(value) ? value.map(String) : [],
      text: Array.isArray(value) ? value.map(String).join(", ") : typeof value === "string" || typeof value === "number" ? String(value) : "",
    } ]
  })
}

// The drafts as the rule engine stores them: a list for is one of, nothing for is empty, words for the rest.
export function storedConditions(drafts: ConditionDraft[]): { field: string; operator: string; value?: string | string[] }[] {
  return drafts.map((draft) => {
    if (draft.operator === EMPTY) {
      return { field: draft.field, operator: draft.operator }
    }
    return { field: draft.field, operator: draft.operator, value: draft.operator === ONE_OF ? draft.values : draft.text.trim() }
  })
}

function valuePlaceholder(operator: ConditionOperator): string {
  if (operator === ALERT_CONDITION_OPERATOR.MATCHES_REGEX) {
    return "A pattern, such as ^checkout"
  }
  return comparesNumbers(operator) ? "A number, such as 20" : "Value"
}

export function conditionsError(drafts: ConditionDraft[]): string | null {
  if (drafts.some((draft) => draft.field.length === 0)) {
    return "Choose what each condition reads."
  }
  if (drafts.some((draft) => draft.operator === ONE_OF && draft.values.length === 0)) {
    return "Give each condition at least one value."
  }
  if (drafts.some((draft) => draft.operator !== ONE_OF && draft.operator !== EMPTY && draft.text.trim().length === 0)) {
    return "Give each condition what it compares with."
  }
  if (drafts.some((draft) => comparesNumbers(draft.operator) && !NUMBER.test(draft.text.trim()))) {
    return "Give each number condition a number, such as 20."
  }
  return null
}

interface TriggerConditionsProps {
  idPrefix: string
  fields: ConditionField[]
  drafts: ConditionDraft[]
  disabled: boolean
  onChange: (drafts: ConditionDraft[]) => void
}

// What must hold of what happened for it to start a run, each condition a field the trigger offers, how it compares
// and what with, the workspace's own values offered where the field has a fixed set. Every condition must hold.
export function TriggerConditions({ idPrefix, fields, drafts, disabled, onChange }: TriggerConditionsProps) {
  const fieldOptions = fields.map((field) => ({ value: field.key, label: field.label }))

  function update(key: string, patch: Partial<ConditionDraft>) {
    onChange(drafts.map((draft) => (draft.key === key ? { ...draft, ...patch } : draft)))
  }

  function add() {
    onChange([ ...drafts, { key: crypto.randomUUID(), field: "", operator: ONE_OF, values: [], text: "" } ])
  }

  function remove(key: string) {
    return () => onChange(drafts.filter((draft) => draft.key !== key))
  }

  return (
    <section className="space-y-2">
      <h4 className="font-mono text-[10.5px] tracking-[0.1em] text-brand uppercase">Only when</h4>
      <p className="text-xs text-fg-muted">
        {drafts.length === 0 ? "It runs every time. Add a condition to run only for some." : "It runs only when every condition holds."}
      </p>
      {drafts.map((draft) => (
        <ConditionRow key={draft.key} idPrefix={`${idPrefix}-${draft.key}`} draft={draft} fields={fields} fieldOptions={fieldOptions}
                      disabled={disabled} onChange={update} onRemove={remove(draft.key)} />
      ))}
      {!disabled && drafts.length < WORKFLOW_CONDITION_LIMIT && (
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={add}>
          <IconPlus className="size-3.5" />
          Add a condition
        </Button>
      )}
    </section>
  )
}

interface ConditionRowProps {
  idPrefix: string
  draft: ConditionDraft
  fields: ConditionField[]
  fieldOptions: { value: string; label: string }[]
  disabled: boolean
  onChange: (key: string, patch: Partial<ConditionDraft>) => void
  onRemove: () => void
}

function ConditionRow({ idPrefix, draft, fields, fieldOptions, disabled, onChange, onRemove }: ConditionRowProps) {
  const field = fields.find((each) => each.key === draft.field)
  const choices = field?.options ?? []
  const operators = operatorsFor(field)
  const known = draft.field.length === 0 || fieldOptions.some((option) => option.value === draft.field)
  const options = known ? fieldOptions : [ { value: draft.field, label: draft.field }, ...fieldOptions ]

  // A number field starts compared as a number, and a field that is not one never keeps a number's comparison.
  function fieldChosen(value: string | null) {
    const chosen = fields.find((each) => each.key === value)
    const offered = operatorsFor(chosen).some((operator) => operator.value === draft.operator)
    const operator = chosen?.number ? TRIGGER_NUMBER_OPERATOR.GREATER_THAN : offered ? draft.operator : ONE_OF
    onChange(draft.key, { field: value ?? "", operator, values: [], text: "" })
  }

  function fieldTyped(event: ChangeEvent<HTMLInputElement>) {
    onChange(draft.key, { field: event.target.value.trim() })
  }

  // Values typed separated by commas, kept as typed so a comma can be written, and as the list they make.
  function typedValues(event: ChangeEvent<HTMLInputElement>) {
    const text = event.target.value
    onChange(draft.key, { text, values: text.split(",").map((part) => part.trim()).filter((part) => part.length > 0) })
  }

  function operatorChosen(value: string) {
    if (isOperator(value)) {
      onChange(draft.key, { operator: value })
    }
  }

  function typed(event: ChangeEvent<HTMLInputElement>) {
    onChange(draft.key, { text: event.target.value })
  }

  function added(value: string) {
    onChange(draft.key, { values: [ ...draft.values, value ] })
  }

  function removed(value: string) {
    onChange(draft.key, { values: draft.values.filter((each) => each !== value) })
  }

  return (
    <div className="space-y-1.5 rounded-md border border-border p-2">
      <div className="flex gap-1.5">
        <div className="min-w-0 flex-1">
          {fields.length > 0 ? (
            <SearchableSelect id={`${idPrefix}-field`} value={draft.field || null} onValueChange={fieldChosen} options={options}
                              placeholder="What it reads" disabled={disabled} />
          ) : (
            <Input id={`${idPrefix}-field`} value={draft.field} aria-label="What it reads" placeholder="What it reads, such as body.service"
                   disabled={disabled} onChange={fieldTyped} />
          )}
        </div>
        {!disabled && (
          <button type="button" aria-label="Remove this condition" className="px-1 text-fg-muted hover:text-destructive" onClick={onRemove}>
            <IconX className="size-4" />
          </button>
        )}
      </div>
      <Select value={draft.operator} onValueChange={operatorChosen} disabled={disabled}>
        <SelectTrigger aria-label="How it compares" className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {operators.map((operator) => (
            <SelectItem key={operator.value} value={operator.value}>{operator.label}</SelectItem>
          ))}
        </SelectContent>
      </Select>
      {draft.operator === ONE_OF && choices.length > 0 && (
        <BadgeMultiSelect stacked selected={draft.values} options={choices} placeholder="Add a value" onAdd={added} onRemove={removed} />
      )}
      {draft.operator === ONE_OF && choices.length === 0 && (
        <Input value={draft.text} aria-label="Values" placeholder="Values, separated by commas" disabled={disabled} onChange={typedValues} />
      )}
      {draft.operator !== ONE_OF && draft.operator !== EMPTY && (
        <Input value={draft.text} aria-label="Value" placeholder={valuePlaceholder(draft.operator)} inputMode={comparesNumbers(draft.operator) ? "decimal" : undefined}
               disabled={disabled} onChange={typed} />
      )}
    </div>
  )
}
