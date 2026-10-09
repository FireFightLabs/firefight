import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"
import { shownValue, type ArgumentsState, type ToolField } from "@/pages/settings/lib/runbook-procedure"

interface ToolFieldInputProps {
  id: string
  field: ToolField
  state: ArgumentsState
  error: string | undefined
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  onChange: (field: ToolField, entered: string | boolean) => void
}

export function ToolFieldInput({ id, field, state, error, placeholders, places, onChange }: ToolFieldInputProps) {
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
          id={id}
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
