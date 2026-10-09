import { IconX } from "@tabler/icons-react"

import type { SearchableSelectOption } from "@/components/searchable-select"
import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"
import { ToolFieldInput } from "@/pages/settings/components/runbooks/tool-field-input"
import {
  otherArguments,
  withField,
  withoutArgument,
  written,
  type ArgumentsState,
  type ToolField,
} from "@/pages/settings/lib/runbook-procedure"

interface RunbookToolFieldsProps {
  idPrefix: string
  // null while the tool's fields are loading, or when this person cannot see the tool, so only what was saved shows.
  fields: ToolField[] | null
  state: ArgumentsState
  errors: Record<string, string>
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (state: ArgumentsState) => void
}

// A field for each of a tool's parameters, made from its schema: text, a number, a choice, a switch or a list. A field
// takes an input as {{key}} wherever a fixed value would go. What the fields do not hold is listed and kept.
export function RunbookToolFields({ idPrefix, fields, state, errors, placeholders, places, onChange }: RunbookToolFieldsProps) {
  const others = otherArguments(fields, state)

  function setField(field: ToolField, entered: string | boolean) {
    onChange(withField(state, field, entered))
  }

  function remove(key: string) {
    onChange(withoutArgument(state, key))
  }

  return (
    <div className="space-y-3">
      {(fields ?? []).filter((field) => field.kind !== RUNBOOK_FIELD_KINDS.KEPT).map((field) => (
        <ToolFieldInput
          key={field.key}
          id={`${idPrefix}-${field.key}`}
          field={field}
          state={state}
          error={errors[field.key]}
          placeholders={placeholders}
          places={places}
          onChange={setField}
        />
      ))}
      {others.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs text-muted-foreground">Also set, and kept as they are</p>
          {others.map(([ key, value ]) => (
            <div key={key} className="flex items-start gap-2 rounded-md bg-muted px-2.5 py-1.5 font-mono text-xs">
              <span className="min-w-0 flex-1 [overflow-wrap:anywhere]">
                <span className="text-muted-foreground">{key}: </span>
                {written(value)}
              </span>
              <button type="button" aria-label={`Remove ${key}`} className="text-fg-muted hover:text-destructive" onClick={() => remove(key)}>
                <IconX className="size-3.5" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
