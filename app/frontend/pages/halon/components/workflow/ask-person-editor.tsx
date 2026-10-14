import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_ASK_PERSON } from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"
import { FieldsEditor } from "@/pages/halon/components/workflow/fields-editor"
import { NamedRows, newRow, ROW_NAME, type NamedRow } from "@/pages/halon/components/workflow/named-rows"
import type { WorkflowStepKind } from "@/types/serializers"

interface AskPersonEditorProps {
  idPrefix: string
  kind: WorkflowStepKind | null
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function savedFields(config: JsonObject): NamedRow[] {
  const saved = config[WORKFLOW_ASK_PERSON.FIELDS]
  return (Array.isArray(saved) ? saved : []).filter(isObject)
    .map((field) => newRow(String(field[WORKFLOW_ASK_PERSON.FIELD_NAME] ?? ""), String(field[WORKFLOW_ASK_PERSON.FIELD_LABEL] ?? "")))
}

// The settings the field form draws, without the short form this editor draws itself.
function withoutForm(config: JsonObject): JsonObject {
  return Object.fromEntries(Object.entries(config).filter(([ key ]) => key !== WORKFLOW_ASK_PERSON.FIELDS))
}

function formError(rows: NamedRow[]): string | null {
  if (rows.some((row) => !ROW_NAME.test(row.name.trim()))) {
    return "Name each field in lowercase letters, numbers and underscores."
  }
  return rows.some((row) => row.text.trim().length === 0) ? "Say what each field asks." : null
}

// An Ask a person step: who it asks, the question, its choices, each a route out of the step, and a short form whose
// answers later steps read by name.
export function AskPersonEditor({ idPrefix, kind, config, references, disabled, onChange }: AskPersonEditorProps) {
  const [ rows, setRows ] = useState<NamedRow[]>(() => savedFields(config))
  const [ values, setValues ] = useState<JsonObject>(() => withoutForm(config))

  function stored(next: NamedRow[]) {
    return next.map((row) => ({ [WORKFLOW_ASK_PERSON.FIELD_NAME]: row.name.trim(), [WORKFLOW_ASK_PERSON.FIELD_LABEL]: row.text.trim() }))
  }

  function fieldsChanged(next: JsonObject) {
    setValues(next)
    onChange({ ...next, [WORKFLOW_ASK_PERSON.FIELDS]: stored(rows) }, formError(rows))
  }

  function formChanged(next: NamedRow[]) {
    setRows(next)
    onChange({ ...values, [WORKFLOW_ASK_PERSON.FIELDS]: stored(next) }, formError(next))
  }

  return (
    <div className="space-y-3">
      <FieldsEditor idPrefix={idPrefix} fields={kind?.fields ?? []} values={withoutForm(config)} references={references} disabled={disabled} onChange={fieldsChanged} />
      <NamedRows title="Short form" rows={rows} limit={WORKFLOW_ASK_PERSON.FIELD_LIMIT} namePlaceholder="reason" textPlaceholder="Why roll back?"
                 textLabel="What it asks" addLabel="Add a field" disabled={disabled} onChange={formChanged} />
      <p className="text-xs text-muted-foreground">Give choices, a short form, or both. Later steps read each field by its name.</p>
    </div>
  )
}
