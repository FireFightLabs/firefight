import type { ChangeEvent } from "react"

import { SearchableSelect, type SearchableSelectOption } from "@/components/searchable-select"
import { ChoiceListInput } from "@/components/tool-fields/choice-list-input"
import { ReferencePicker } from "@/components/tool-fields/reference-picker"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { RUNBOOK_FIELD_KINDS } from "@/lib/generated/constants"
import { shownValue, type ArgumentsState, type ToolField } from "@/lib/tool-fields"

interface ToolFieldInputProps {
  id: string
  field: ToolField
  state: ArgumentsState
  error: string | undefined
  placeholders: SearchableSelectOption[]
  places: SearchableSelectOption[]
  // What a text field can be filled from, such as an earlier workflow step's fields, offered beside it.
  references?: SearchableSelectOption[]
  disabled?: boolean
  onChange: (field: ToolField, entered: string | boolean) => void
}

export function ToolFieldInput({ id, field, state, error, placeholders, places, references = [], disabled = false, onChange }: ToolFieldInputProps) {
  const shown = shownValue(field, state)
  const choiceList = field.kind === RUNBOOK_FIELD_KINDS.LIST && field.options.length > 0

  function typed(event: ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) {
    onChange(field, event.target.value)
  }

  function chosen(value: string | null) {
    onChange(field, value ?? "")
  }

  function toggled(checked: boolean) {
    onChange(field, checked)
  }

  function inserted(reference: string) {
    onChange(field, `${shown}${reference}`)
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={id} className="text-xs">
        {field.key}
        {field.required && <span className="text-destructive"> *</span>}
      </Label>
      {field.kind === RUNBOOK_FIELD_KINDS.TOGGLE && (
        <div className="flex items-center gap-2">
          <Switch id={id} checked={state.values[field.key] === true} onCheckedChange={toggled} disabled={disabled} />
        </div>
      )}
      {(field.kind === RUNBOOK_FIELD_KINDS.SELECT || field.kind === RUNBOOK_FIELD_KINDS.RESOURCE) && (
        <SearchableSelect
          id={id}
          disabled={disabled}
          value={shown || null}
          onValueChange={chosen}
          options={choiceOptions(field, shown, placeholders, places)}
          placeholder={field.required ? "Choose one" : "Choose one (optional)"}
        />
      )}
      {choiceList && <ChoiceListInput field={field} selected={chosenList(state, field)} disabled={disabled} onChange={onChange} />}
      {(field.kind === RUNBOOK_FIELD_KINDS.TEXT || field.kind === RUNBOOK_FIELD_KINDS.NUMBER || (field.kind === RUNBOOK_FIELD_KINDS.LIST && !choiceList)) && (
        <div className="flex gap-1.5">
          <Input
            id={id}
            value={shown}
            onChange={typed}
            disabled={disabled}
            inputMode={field.kind === RUNBOOK_FIELD_KINDS.NUMBER ? "numeric" : undefined}
            placeholder={field.kind === RUNBOOK_FIELD_KINDS.LIST ? "Separated by commas" : field.required ? "" : "Optional"}
            aria-invalid={error != null}
          />
          {references.length > 0 && !disabled && <ReferencePicker references={references} label={`Use an earlier value in ${field.key}`} onPick={inserted} />}
        </div>
      )}
      {field.kind === RUNBOOK_FIELD_KINDS.PARAGRAPH && (
        <div className="flex gap-1.5">
          <Textarea id={id} value={shown} onChange={typed} disabled={disabled} rows={3} placeholder={field.required ? "" : "Optional"} aria-invalid={error != null} />
          {references.length > 0 && !disabled && <ReferencePicker references={references} label={`Use an earlier value in ${field.key}`} onPick={inserted} />}
        </div>
      )}
      {field.description && <p className="text-xs text-muted-foreground">{field.description}</p>}
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}

// The values chosen in a list field with a fixed set of them.
function chosenList(state: ArgumentsState, field: ToolField): string[] {
  const value = state.values[field.key]
  return Array.isArray(value) ? value.map(String) : []
}

// A choice's own values, or what is on the map, with the inputs that can stand in for one, and a saved value that is
// neither so it still shows.
function choiceOptions(field: ToolField, shown: string, placeholders: SearchableSelectOption[], places: SearchableSelectOption[]): SearchableSelectOption[] {
  const own = field.kind === RUNBOOK_FIELD_KINDS.RESOURCE ? places : field.options.map((option) => ({ value: option, label: option }))
  const options = [ ...own, ...placeholders ]
  const saved = shown.length > 0 && !options.some((option) => option.value === shown) ? [ { value: shown, label: shown } ] : []
  return [ ...saved, ...options ]
}
