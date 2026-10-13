import { useState } from "react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { WORKFLOW_SET_DATA } from "@/lib/generated/constants"
import { isObject, type JsonObject } from "@/lib/tool-fields"
import { NamedRows, newRow, ROW_NAME, type NamedRow } from "@/pages/halon/components/workflow/named-rows"

interface SetDataEditorProps {
  config: JsonObject
  references: SearchableSelectOption[]
  disabled: boolean
  onChange: (config: JsonObject, error: string | null) => void
}

function savedRows(config: JsonObject): NamedRow[] {
  const saved = config[WORKFLOW_SET_DATA.VALUES]
  return (Array.isArray(saved) ? saved : []).filter(isObject)
    .map((entry) => newRow(String(entry[WORKFLOW_SET_DATA.NAME] ?? ""), String(entry[WORKFLOW_SET_DATA.VALUE] ?? "")))
}

function valuesError(rows: NamedRow[]): string | null {
  if (rows.length === 0) {
    return "Name at least one value."
  }
  if (rows.some((row) => !ROW_NAME.test(row.name.trim()))) {
    return "Name each value in lowercase letters, numbers and underscores."
  }
  return new Set(rows.map((row) => row.name.trim())).size === rows.length ? null : "Name each value once."
}

// A Set data step: each value's name, read later as {{steps.<step>.<name>}}, and its value. One that is only a reference
// keeps its type, and text written as a JSON object or list becomes one.
export function SetDataEditor({ config, references, disabled, onChange }: SetDataEditorProps) {
  const [ rows, setRows ] = useState<NamedRow[]>(() => savedRows(config))

  function changed(next: NamedRow[]) {
    setRows(next)
    const values = next.map((row) => ({ [WORKFLOW_SET_DATA.NAME]: row.name.trim(), [WORKFLOW_SET_DATA.VALUE]: row.text }))
    onChange({ ...config, [WORKFLOW_SET_DATA.VALUES]: values }, valuesError(next))
  }

  return (
    <div className="space-y-2">
      <NamedRows title="Values" rows={rows} limit={WORKFLOW_SET_DATA.LIMIT} namePlaceholder="service" textPlaceholder="{{trigger.alert.service}}"
                 textLabel="Its value" addLabel="Add a value" references={references} disabled={disabled} onChange={changed} />
      <p className="text-xs text-muted-foreground">A value that is only a reference keeps its type. Write a JSON object or list to reshape data.</p>
    </div>
  )
}
