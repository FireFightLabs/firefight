import { IconX } from "@tabler/icons-react"
import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"
import {
  otherArguments,
  shownValue,
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

interface ToolFieldInputProps {
  id: string
  field: ToolField
  state: ArgumentsState
  error: string | undefined
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (field: ToolField, entered: string | boolean) => void
}

function ToolFieldInput({ id, field, state, error, placeholders, places, onChange }: ToolFieldInputProps) {
  const shown = shownValue(field, state)

  function typed(event: ChangeEvent<HTMLInputElement>) {
    onChange(field, event.target.value)
  }

  function chosen(value: string | null) {
    onChange(field, value ?? "")
  }

  function toggled(checked: boolean) {
    onChange(field, checked)
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={id} className="text-xs">
        {field.key}
        {field.required && <span className="text-destructive"> *</span>}
      </Label>
      {field.kind === RUNBOOK_FIELD_KINDS.TOGGLE && (
        <div className="flex items-center gap-2">
          <Switch id={id} checked={state.values[field.key] === true} onCheckedChange={toggled} />
        </div>
      )}
      {(field.kind === RUNBOOK_FIELD_KINDS.SELECT || field.kind === RUNBOOK_FIELD_KINDS.RESOURCE) && (
        <SearchableSelect
          value={shown || null}
          onValueChange={chosen}
          options={choiceOptions(field, shown, placeholders, places)}
          placeholder={field.required ? "Choose one" : "Choose one (optional)"}
        />
      )}
      {(field.kind === RUNBOOK_FIELD_KINDS.TEXT || field.kind === RUNBOOK_FIELD_KINDS.NUMBER || field.kind === RUNBOOK_FIELD_KINDS.LIST) && (
        <Input
          id={id}
          value={shown}
          onChange={typed}
          inputMode={field.kind === RUNBOOK_FIELD_KINDS.NUMBER ? "numeric" : undefined}
          placeholder={field.kind === RUNBOOK_FIELD_KINDS.LIST ? "Separated by commas" : field.required ? "" : "Optional"}
          aria-invalid={error != null}
        />
      )}
      {field.description && <p className="text-xs text-muted-foreground">{field.description}</p>}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}

// A choice's own values, or what is on the map, with the inputs that can stand in for one, and a saved value that is
// neither so it still shows.
function choiceOptions(field: ToolField, shown: string, placeholders: SearchableSelectOption[], places: SearchableSelectOption[]): SearchableSelectOption[] {
  const own = field.kind === RUNBOOK_FIELD_KINDS.RESOURCE ? places : field.options.map((option) => ({ value: option, label: option }))
  const options = [ ...own, ...placeholders ]
  const saved = shown.length > 0 && !options.some((option) => option.value === shown) ? [ { value: shown, label: shown } ] : []
  return [ ...saved, ...options ]
}
