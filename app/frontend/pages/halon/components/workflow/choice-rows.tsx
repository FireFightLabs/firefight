import { IconPlus, IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { WORKFLOW_ASK_PERSON } from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"

// One choice as it is being written: the words on its button, and the key its route is named by, which Firefight gives
// it when it is first saved and keeps when the words change. A new choice has none yet.
export interface ChoiceRow {
  row: string
  key: string
  label: string
}

export function savedChoices(config: JsonObject): ChoiceRow[] {
  const saved = config[WORKFLOW_ASK_PERSON.CHOICES]
  return (Array.isArray(saved) ? saved : []).map((choice) => {
    const kept = isObject(choice) ? choice : { [WORKFLOW_ASK_PERSON.CHOICE_LABEL]: String(choice) }
    return { row: crypto.randomUUID(), key: String(kept[WORKFLOW_ASK_PERSON.CHOICE_KEY] ?? ""), label: String(kept[WORKFLOW_ASK_PERSON.CHOICE_LABEL] ?? "") }
  })
}

// The choices as they are kept. A new one is sent with its words alone, and the server gives it its key.
export function storedChoices(rows: ChoiceRow[]): JsonObject[] {
  return rows.map((choice) => {
    const label = { [WORKFLOW_ASK_PERSON.CHOICE_LABEL]: choice.label.trim() }
    return choice.key ? { [WORKFLOW_ASK_PERSON.CHOICE_KEY]: choice.key, ...label } : label
  })
}

export function choicesError(rows: ChoiceRow[]): string | null {
  const labels = rows.map((choice) => choice.label.trim())
  if (labels.some((label) => label.length === 0)) {
    return "Write the words on each choice's button."
  }
  if (labels.some((label) => label.length > WORKFLOW_ASK_PERSON.CHOICE_LABEL_LIMIT)) {
    return `Keep each choice to ${WORKFLOW_ASK_PERSON.CHOICE_LABEL_LIMIT} characters.`
  }
  return new Set(labels.map((label) => label.toLowerCase())).size === labels.length ? null : "Give each choice different words."
}

interface ChoiceRowsProps {
  rows: ChoiceRow[]
  disabled: boolean
  onChange: (rows: ChoiceRow[]) => void
}

// The choices a person picks from, each written as the words on its button and each a way out of the step.
export function ChoiceRows({ rows, disabled, onChange }: ChoiceRowsProps) {
  function typed(row: string) {
    return (event: ChangeEvent<HTMLInputElement>) => onChange(rows.map((choice) => (choice.row === row ? { ...choice, label: event.target.value } : choice)))
  }

  function add() {
    onChange([ ...rows, { row: crypto.randomUUID(), key: "", label: "" } ])
  }

  function remove(row: string) {
    return () => onChange(rows.filter((choice) => choice.row !== row))
  }

  return (
    <section className="space-y-2">
      <h4 className="text-xs font-medium text-fg-secondary">Choices</h4>
      {rows.map((choice, index) => (
        <div key={choice.row} className="flex gap-1.5">
          <Input value={choice.label} onChange={typed(choice.row)} placeholder={index === 0 ? "Roll back now" : "Wait for the fix"} aria-label="Words on the button"
                 maxLength={WORKFLOW_ASK_PERSON.CHOICE_LABEL_LIMIT} disabled={disabled} />
          {!disabled && (
            <button type="button" aria-label={`Remove ${choice.label || "this choice"}`} className="px-1 text-fg-muted hover:text-destructive" onClick={remove(choice.row)}>
              <IconX className="size-4" />
            </button>
          )}
        </div>
      ))}
      {!disabled && rows.length < WORKFLOW_ASK_PERSON.CHOICE_LIMIT && (
        <Button type="button" variant="outline" size="sm" className="h-7 gap-1 px-2 text-xs" onClick={add}>
          <IconPlus className="size-3.5" />
          Add a choice
        </Button>
      )}
    </section>
  )
}
