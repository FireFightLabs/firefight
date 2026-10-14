import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_ASK_PERSON, WORKFLOW_WAIT } from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"
import { ChoiceRows, type ChoiceRow, choicesError, savedChoices, storedChoices } from "@/pages/halon/components/workflow/choice-rows"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { NamedRows, newRow, ROW_NAME, type NamedRow } from "@/pages/halon/components/workflow/named-rows"
import { savedWait, WaitForField, waitError } from "@/pages/halon/components/workflow/wait-for-field"
import type { WorkflowStepKind } from "@/types/serializers"

interface AskPersonEditorProps {
  idPrefix: string
  kind: WorkflowStepKind | null
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

// The settings this editor draws itself, kept out of the field form.
const OWN_KEYS: string[] = [ WORKFLOW_ASK_PERSON.FIELDS, WORKFLOW_ASK_PERSON.CHOICES, WORKFLOW_WAIT.KEY ]

function savedFields(config: JsonObject): NamedRow[] {
  const saved = config[WORKFLOW_ASK_PERSON.FIELDS]
  return (Array.isArray(saved) ? saved : []).filter(isObject)
    .map((field) => newRow(String(field[WORKFLOW_ASK_PERSON.FIELD_NAME] ?? ""), String(field[WORKFLOW_ASK_PERSON.FIELD_LABEL] ?? "")))
}

function withoutOwn(config: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(config).filter(([ key ]) => !OWN_KEYS.includes(key)))
}

function formError(rows: NamedRow[]): string | null {
  if (rows.some((row) => !ROW_NAME.test(row.name.trim()))) {
    return "Name each field in lowercase letters, numbers and underscores."
  }
  return rows.some((row) => row.text.trim().length === 0) ? "Say what each field asks." : null
}

interface AskDraft {
  values: JsonObject
  choices: ChoiceRow[]
  fields: NamedRow[]
  wait: number | null
}

// An Ask a person step: who it asks, the question, its choices, each written as the words on its button and each a
// route out of the step, a short form whose answers later steps read by name, and how long it waits for an answer.
export function AskPersonEditor({ idPrefix, kind, config, references, disabled, onChange }: AskPersonEditorProps) {
  const [ draft, setDraft ] = useState<AskDraft>(() => ({
    values: withoutOwn(config), choices: savedChoices(config), fields: savedFields(config), wait: savedWait(config),
  }))

  function send(next: AskDraft) {
    setDraft(next)
    const fields = next.fields.map((row) => ({ [WORKFLOW_ASK_PERSON.FIELD_NAME]: row.name.trim(), [WORKFLOW_ASK_PERSON.FIELD_LABEL]: row.text.trim() }))
    const stored = { ...next.values, [WORKFLOW_ASK_PERSON.CHOICES]: storedChoices(next.choices), [WORKFLOW_ASK_PERSON.FIELDS]: fields, [WORKFLOW_WAIT.KEY]: next.wait }
    onChange(stored, choicesError(next.choices) ?? formError(next.fields) ?? waitError(next.wait))
  }

  function fieldsChanged(values: JsonObject) {
    send({ ...draft, values })
  }

  function choicesChanged(choices: ChoiceRow[]) {
    send({ ...draft, choices })
  }

  function formChanged(fields: NamedRow[]) {
    send({ ...draft, fields })
  }

  function waitChanged(wait: number | null) {
    send({ ...draft, wait })
  }

  return (
    <div className="space-y-3">
      <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={withoutOwn(config)} references={references} disabled={disabled} onChange={fieldsChanged} />
      <ChoiceRows rows={draft.choices} disabled={disabled} onChange={choicesChanged} />
      <p className="text-xs text-muted-foreground">Each choice is a button with these words, and a way out of the step to connect.</p>
      <NamedRows title="Short form" rows={draft.fields} limit={WORKFLOW_ASK_PERSON.FIELD_LIMIT} namePlaceholder="reason" textPlaceholder="Why roll back?"
                 textLabel="What it asks" addLabel="Add a field" disabled={disabled} onChange={formChanged} />
      <p className="text-xs text-muted-foreground">Give choices, a short form, or both. Later steps read each field by its name.</p>
      <WaitForField idPrefix={idPrefix} minutes={draft.wait ?? savedWait(config)} hint="If nobody answers by then, the step takes its unanswered way out."
                    disabled={disabled} onChange={waitChanged} />
    </div>
  )
}
